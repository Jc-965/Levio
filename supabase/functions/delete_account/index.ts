// Deletes the calling user's auth identity after removing their data.
//
// The client cannot delete a Supabase auth user with the publishable key,
// so "Delete Account" must go through this function or the email/OAuth
// identity survives forever. Deploy with:
//   supabase functions deploy delete_account
// Requires the service role key, which the Edge runtime injects as
// SUPABASE_SERVICE_ROLE_KEY.

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  // Resolve the caller from their JWT with the anon key; the privileged
  // client below is used only after the identity is proven.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser(authHeader.replace("Bearer ", ""));
  if (userError || !user) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // Row deletions cascade from users; delete the row first so a failure
  // never leaves data without an owning auth identity.
  const { error: rowError } = await admin
    .from("users")
    .delete()
    .eq("id", user.id);
  if (rowError) {
    return new Response(JSON.stringify({ error: "data_deletion_failed" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { error: authError } = await admin.auth.admin.deleteUser(user.id);
  if (authError) {
    return new Response(JSON.stringify({ error: "auth_deletion_failed" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
