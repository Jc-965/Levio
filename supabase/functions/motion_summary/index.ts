// Generates a short plain-language summary of one motion coach session.
//
// The deterministic metrics remain the source of truth: this function only
// rephrases numbers that already exist in the session's evidence document,
// and its output is validated so a summary that invents a number is
// discarded rather than shown. Summaries are cached on the session row, so
// each session is generated at most once, and only its owner can request it.
//
// Deploy with JWT verification ON (the default):
//   supabase functions deploy motion_summary
// Secrets:
//   supabase secrets set ANTHROPIC_API_KEY=...

import { createClient } from "jsr:@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk";
import { extractAllowedNumbers, validateSummary } from "./validate.ts";

const MODEL = "claude-opus-5";
const MAX_SUMMARIES_PER_DAY = 20;
const MAX_ATTEMPTS_PER_SESSION = 3;

const SYSTEM_PROMPT = [
  "You turn exercise-session measurements into a short, warm summary for a",
  "person with Parkinson's disease using a wellness app.",
  "Hard rules:",
  "- At most 80 words, plain language, second person, encouraging tone.",
  "- Only restate numbers that appear in the provided JSON. Never compute,",
  "  estimate, or invent any number, percentage, or comparison.",
  "- No diagnosis, no medical claims, no medication or treatment advice,",
  "  and no instructions to change their exercise plan.",
  "- Do not mention JSON, data, or these rules.",
].join("\n");

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  // Resolve the caller from their JWT with the anon key; the privileged
  // client is used only after the identity is proven.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser(authHeader.replace("Bearer ", ""));
  if (userError || !user) {
    return json({ error: "unauthorized" }, 401);
  }
  if (user.is_anonymous) {
    // Anonymous bootstrap sessions hold no synced health data and must not
    // be able to spend summary quota.
    return json({ error: "full_account_required" }, 403);
  }

  let sessionId = "";
  try {
    const body = await req.json();
    sessionId = typeof body?.session_id === "string" ? body.session_id : "";
  } catch (_) {
    // Falls through to the empty-id rejection below.
  }
  if (!sessionId || sessionId.length > 64) {
    return json({ error: "invalid_session_id" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data: row, error: rowError } = await admin
    .from("motion_sessions")
    .select(
      "id, llm_summary, record, evaluation, overall_score, completed_at, routine_name",
    )
    .eq("id", sessionId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (rowError) {
    return json({ error: "lookup_failed" }, 500);
  }
  if (!row) {
    return json({ error: "not_found" }, 404);
  }
  if (typeof row.llm_summary === "string" && row.llm_summary.length > 0) {
    return json({ summary: row.llm_summary, cached: true });
  }

  // Structural cost bound: one generation per session row, plus a per-user
  // daily ceiling. The attempt timestamp below is written BEFORE the model
  // call, so failed or discarded generations count against the ceiling too;
  // otherwise a client looping on a session whose output keeps failing
  // validation would have unbounded spend.
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count, error: countError } = await admin
    .from("motion_sessions")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gt("llm_summary_generated_at", since);
  if (countError || (count ?? 0) >= MAX_SUMMARIES_PER_DAY) {
    // A failed count fails CLOSED: for an optional feature, briefly
    // unavailable beats unmetered.
    return json(
      countError ? { summary: null } : { error: "rate_limited" },
      countError ? 200 : 429,
    );
  }
  // Atomic attempt claim: a single SQL statement increments the counter
  // and stamps the attempt time only while the session is under its
  // budget, so concurrent duplicates and repeatedly-failing generations
  // are both hard-bounded (total daily spend <= sessions x attempts).
  const { data: claimed, error: attemptError } = await admin.rpc(
    "claim_motion_summary_attempt",
    {
      p_session_id: sessionId,
      p_user_id: user.id,
      p_max_attempts: MAX_ATTEMPTS_PER_SESSION,
    },
  );
  if (attemptError || claimed !== true) {
    return json({ summary: null }, 200);
  }

  // Recent trend context: scores and day-level dates only, never identity.
  const { data: recent } = await admin
    .from("motion_sessions")
    .select("overall_score, completed_at")
    .eq("user_id", user.id)
    .order("completed_at", { ascending: false })
    .limit(10);
  const trend = (recent ?? []).map((entry) => ({
    overall_score: entry.overall_score,
    day: String(entry.completed_at ?? "").slice(0, 10),
  }));

  const input = {
    session: row.record ?? {},
    evaluation_summary: (row.evaluation as Record<string, unknown>)?.summary ??
      null,
    recent_sessions: trend,
  };

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return json({ summary: null, error: "not_configured" }, 200);
  }
  const anthropic = new Anthropic({ apiKey });
  let text = "";
  try {
    const response = await anthropic.beta.messages.create({
      model: MODEL,
      max_tokens: 1024,
      output_config: { effort: "low" },
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: "Session measurements:\n" + JSON.stringify(input),
        },
      ],
    });
    if (response.stop_reason !== "end_turn") {
      // Includes safety declines (stop_reason "refusal"); the app falls
      // back to its deterministic summary.
      return json({ summary: null }, 200);
    }
    for (const block of response.content) {
      if (block.type === "text") text += block.text;
    }
  } catch (_) {
    return json({ summary: null }, 200);
  }

  const summary = text.trim();
  const allowed = extractAllowedNumbers(input);
  if (!validateSummary(summary, allowed)) {
    // A summary that invents a number or overruns the cap never reaches a
    // person and is not cached; the next request may try again.
    return json({ summary: null }, 200);
  }

  await admin
    .from("motion_sessions")
    .update({
      llm_summary: summary,
      llm_summary_model: MODEL,
      llm_summary_generated_at: new Date().toISOString(),
    })
    .eq("id", sessionId)
    .eq("user_id", user.id);

  return json({ summary, cached: false });
});

function json(payload: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
