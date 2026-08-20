# Motion coach feedback architecture

The motion coach gives feedback in three tiers. Each tier degrades
gracefully to the one below it, and the app is fully functional with only
the first.

## Tier 1 — deterministic, on-device, always available

All measurement and coaching runs on the phone with no network:

- MediaPipe's bundled pose model tracks 33 body landmarks per camera frame.
- The vendored `motion_engine` package counts, times, and scores every
  repetition, speaks allowlisted cues live, and produces the post-session
  evaluation document.
- Every sentence shown or spoken comes from a reviewed allowlist keyed to
  machine-readable engine codes. Nothing user-facing is generated.

This tier is the source of truth. Scores, evidence chips, reason codes,
trend deltas, and cue-frequency insights all come from it.

## Tier 2 — account backup (opt-out, signed-in accounts)

Derived results only (scores, repetition counts, allowlisted sentences)
sync to the person's account through the app's offline mutation journal.
Camera frames, video, and pose landmarks are never uploaded. Controlled by
the "Back up results to my account" toggle.

## Tier 3 — cloud AI summary (opt-in, off by default)

An optional edge function (`supabase/functions/motion_summary`) asks a
Claude model to rephrase one synced session's metrics as a short,
encouraging paragraph.

Safety properties, enforced in code rather than by prompt alone:

- Requires a signed-in, non-anonymous account and RLS-scoped row ownership.
- Input is the session's own evidence document plus day-level score trend;
  no identity fields are sent.
- Output is validated deterministically: length caps and a number-echo
  guard that rejects any summary containing a number not present in the
  input. Rejected output is discarded, never shown.
- One generation per session (cached on the row) plus a per-user daily
  ceiling bounds cost structurally.
- Any failure, offline state, or refusal renders nothing; Tier 1 feedback
  is always present.

Deployment: `supabase functions deploy motion_summary` (leave JWT
verification on) and `supabase secrets set ANTHROPIC_API_KEY=...`.

## Why the AI tier is not on-device today

An on-device language model was evaluated and deliberately deferred:

- Usable on-device LLMs add roughly 0.5 GB to the install and need recent
  flagship hardware; this app targets older phones held by older hands.
- Platform-provided models (Apple Foundation Models on iOS 26+, Gemini
  Nano on a small set of Android devices) cover too little of the install
  base to be the only path, so the secure cloud route would still need to
  exist.
- The deterministic tier already delivers the clinically meaningful
  feedback offline; the AI tier is tone, not information.

If platform on-device models become broadly available, the summary call
site is a single function (`getMotionSessionSummary`) behind the same
opt-in toggle, so an on-device provider can replace the edge function
without touching the feedback architecture.
