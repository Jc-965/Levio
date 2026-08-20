-- ParkiWell Supabase schema (production-hardened)
--
-- This schema assumes Supabase Auth is enabled.
-- The mobile app establishes an authenticated session (anonymous or user auth)
-- and RLS binds write operations to auth.uid().

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create or replace function public.current_uid()
returns text
language sql
stable
as $$
  select auth.uid()::text;
$$;

-- True only for sessions belonging to a real, explicitly created account.
-- Anonymous bootstrap sessions also hold the authenticated role, so every
-- health-data policy must restate this rather than rely on the role alone.
create or replace function public.is_full_account()
returns boolean
language sql
stable
as $$
  select coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false;
$$;

create table if not exists public.users (
  id text primary key,
  name text not null default '[Name]',
  email text,
  age integer not null default 0,
  profile_image text,
  -- Server-reserved community alias (Member-NNNNNN). Owned by exactly one
  -- account so nobody can post under another member's established alias,
  -- and stable across the owner's devices and reinstalls.
  community_alias text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.users add column if not exists community_alias text;

create table if not exists public.logs (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  title text not null,
  data text not null,
  event_time text,
  symptom text,
  severity text,
  client_updated_at timestamptz not null default timezone('utc', now()),
  last_mutation_id text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.schedules (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  title text not null,
  data text not null,
  details text,
  days text,
  client_updated_at timestamptz not null default timezone('utc', now()),
  last_mutation_id text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.recovery_sessions (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  type text not null check (type in ('physical', 'speech')),
  video_id text not null,
  title text not null,
  completed_at timestamptz not null default timezone('utc', now()),
  client_updated_at timestamptz not null default timezone('utc', now()),
  last_mutation_id text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.medication_events (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  schedule_id text,
  medication_name text not null,
  scheduled_at timestamptz not null,
  taken_at timestamptz,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'taken', 'skipped')),
  client_updated_at timestamptz not null default timezone('utc', now()),
  last_mutation_id text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.sync_tombstones (
  entity_type text not null,
  entity_id text not null,
  user_id text not null references public.users(id) on delete cascade,
  deleted_at timestamptz not null,
  mutation_id text not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (entity_type, entity_id, user_id)
);

-- Remote feature availability. Read-only from clients: rows are flipped from
-- the dashboard (service role) so a misbehaving feature can be disabled
-- without a store release. Clients cache the last fetched value and treat
-- fetch failure as "keep the cached value", so this table being unreachable
-- can never turn features off on its own.
create table if not exists public.app_flags (
  key text primary key,
  enabled boolean not null default true,
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.app_flags enable row level security;

drop policy if exists app_flags_read_all on public.app_flags;
create policy app_flags_read_all on public.app_flags
  for select to authenticated, anon using (true);
-- No insert/update/delete policies: client roles cannot write flags.

insert into public.app_flags (key, enabled)
  values ('motion_coach', true)
  on conflict (key) do nothing;

-- Motion coach session results: derived scores and repetition evidence only,
-- never video or pose landmarks. `record` is the app's parsed session record
-- (what history screens render); `evaluation` is the engine's raw
-- session-evaluation.v1 evidence document. Size caps keep a malformed or
-- runaway document from bloating rows; an oversized payload rejects only its
-- own mutation. The llm_summary columns are written exclusively by the
-- motion_summary edge function (service role) and are deliberately absent
-- from the sync upsert so a replayed mutation can never clobber a cached
-- summary.
create table if not exists public.motion_sessions (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  routine_id text not null,
  routine_name text not null,
  engine_version text not null,
  completed_at timestamptz not null,
  overall_score double precision,
  record jsonb not null default '{}'::jsonb,
  evaluation jsonb not null default '{}'::jsonb,
  llm_summary text,
  llm_summary_model text,
  llm_summary_generated_at timestamptz,
  llm_summary_attempts integer not null default 0,
  client_updated_at timestamptz not null default timezone('utc', now()),
  last_mutation_id text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.motion_sessions
  drop constraint if exists motion_sessions_field_length_caps;
alter table public.motion_sessions
  add constraint motion_sessions_field_length_caps check (
    length(id) <= 64
    and length(routine_id) <= 64
    and length(routine_name) <= 120
    and length(engine_version) <= 32
    and pg_column_size(record) <= 65536
    and pg_column_size(evaluation) <= 131072
    and (llm_summary is null or length(llm_summary) <= 2000)
  );

alter table public.motion_sessions
  add column if not exists llm_summary_attempts integer not null default 0;

create index if not exists idx_motion_sessions_user_completed
  on public.motion_sessions(user_id, completed_at desc);

-- Bulk deletion for "delete my movement history": removes every motion
-- session the caller owns and tombstones each id so other devices' pending
-- upserts cannot resurrect them. The per-id mutation path only covers the
-- sessions a device still holds locally (capped), so a server-side sweep is
-- required for the deletion promise to hold for long histories.
create or replace function public.delete_my_motion_sessions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id text;
  v_deleted integer;
begin
  v_user_id := public.current_uid();
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Anonymous sessions may not modify health data';
  end if;

  insert into public.sync_tombstones (
    entity_type, entity_id, user_id, deleted_at, mutation_id
  )
  select 'motionSession', id, v_user_id, timezone('utc', now()),
         gen_random_uuid()::text
  from public.motion_sessions
  where user_id = v_user_id
  on conflict (entity_type, entity_id, user_id) do update
    set deleted_at = excluded.deleted_at,
        mutation_id = excluded.mutation_id;

  delete from public.motion_sessions where user_id = v_user_id;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.delete_my_motion_sessions() from public;
grant execute on function public.delete_my_motion_sessions() to authenticated;

-- Atomic attempt accounting for the AI summary edge function. Increments
-- and checks in one statement so concurrent requests cannot overrun the
-- per-session budget. Service-role only: the edge function has already
-- verified the caller owns the session.
create or replace function public.claim_motion_summary_attempt(
  p_session_id text,
  p_user_id text,
  p_max_attempts integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed boolean := false;
begin
  update public.motion_sessions
    set llm_summary_attempts = llm_summary_attempts + 1,
        llm_summary_generated_at = timezone('utc', now())
  where id = p_session_id
    and user_id = p_user_id
    and llm_summary_attempts < p_max_attempts;
  v_claimed := found;
  return v_claimed;
end;
$$;

revoke all on function public.claim_motion_summary_attempt(text, text, integer)
  from public;
grant execute on function public.claim_motion_summary_attempt(text, text, integer)
  to service_role;

alter table public.logs
  add column if not exists client_updated_at timestamptz not null
    default timezone('utc', now());
alter table public.logs
  add column if not exists last_mutation_id text not null default '';
alter table public.schedules
  add column if not exists client_updated_at timestamptz not null
    default timezone('utc', now());
alter table public.schedules
  add column if not exists last_mutation_id text not null default '';
alter table public.recovery_sessions
  add column if not exists client_updated_at timestamptz not null
    default timezone('utc', now());
alter table public.recovery_sessions
  add column if not exists last_mutation_id text not null default '';

create table if not exists public.community_posts (
  id text primary key,
  user_id text not null references public.users(id) on delete cascade,
  user_name text not null,
  profile_image text,
  content text not null,
  category text,
  likes integer not null default 0,
  reports integer not null default 0,
  is_flagged boolean not null default false,
  is_hidden boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.community_comments (
  id text primary key,
  post_id text not null references public.community_posts(id) on delete cascade,
  user_id text not null references public.users(id) on delete cascade,
  user_name text not null,
  profile_image text,
  content text not null,
  reports integer not null default 0,
  is_flagged boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.community_post_likes (
  post_id text not null references public.community_posts(id) on delete cascade,
  user_id text not null references public.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (post_id, user_id)
);

create table if not exists public.community_group_memberships (
  group_id text not null,
  user_id text not null references public.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (group_id, user_id)
);

-- Length caps on attacker-controlled text: client ids are UUIDs (36
-- chars) and profile fields have small UI limits, so anything oversized
-- is a modified client attempting storage abuse.
alter table public.users drop constraint if exists users_field_length_caps;
alter table public.users add constraint users_field_length_caps check (
  length(id) <= 64
  and length(name) <= 120
  and (email is null or length(email) <= 254)
  and (community_alias is null or length(community_alias) <= 40)
  and (profile_image is null or length(profile_image) <= 200)
);
alter table public.logs drop constraint if exists logs_field_length_caps;
alter table public.logs add constraint logs_field_length_caps check (
  length(id) <= 64 and length(data) <= 10000
);
alter table public.schedules
  drop constraint if exists schedules_field_length_caps;
alter table public.schedules add constraint schedules_field_length_caps
  check (length(id) <= 64 and length(data) <= 10000);
alter table public.recovery_sessions
  drop constraint if exists recovery_sessions_field_length_caps;
alter table public.recovery_sessions
  add constraint recovery_sessions_field_length_caps
  check (length(id) <= 64 and length(video_id) <= 32
    and length(title) <= 200);
alter table public.medication_events
  drop constraint if exists medication_events_field_length_caps;
alter table public.medication_events
  add constraint medication_events_field_length_caps
  check (length(id) <= 64 and length(medication_name) <= 200
    and (schedule_id is null or length(schedule_id) <= 64));
alter table public.community_posts
  drop constraint if exists posts_field_length_caps;
alter table public.community_posts add constraint posts_field_length_caps
  check (length(id) <= 64 and (category is null or length(category) <= 40));
alter table public.community_comments
  drop constraint if exists comments_field_length_caps;
alter table public.community_comments
  add constraint comments_field_length_caps
  check (length(id) <= 64 and length(post_id) <= 64);

create unique index if not exists users_community_alias_unique
  on public.users (community_alias)
  where community_alias is not null;

create index if not exists idx_logs_user_created
  on public.logs(user_id, created_at desc);
create index if not exists idx_schedules_user_created
  on public.schedules(user_id, created_at desc);
create index if not exists idx_recovery_sessions_user_completed
  on public.recovery_sessions(user_id, completed_at desc);
create index if not exists idx_recovery_sessions_user_video
  on public.recovery_sessions(user_id, type, video_id);
create index if not exists idx_medication_events_user_scheduled
  on public.medication_events(user_id, scheduled_at desc);
create index if not exists idx_medication_events_user_taken
  on public.medication_events(user_id, taken_at desc)
  where taken_at is not null;
create index if not exists idx_sync_tombstones_user_deleted
  on public.sync_tombstones(user_id, deleted_at desc);
create index if not exists idx_posts_created
  on public.community_posts(created_at desc);
create index if not exists idx_posts_user_created
  on public.community_posts(user_id, created_at desc);
create index if not exists idx_comments_post_created
  on public.community_comments(post_id, created_at asc);
create index if not exists idx_comments_user_created
  on public.community_comments(user_id, created_at desc);
create index if not exists idx_post_likes_user_created
  on public.community_post_likes(user_id, created_at desc);
create index if not exists idx_group_memberships_user_created
  on public.community_group_memberships(user_id, created_at desc);
create index if not exists idx_group_memberships_group_created
  on public.community_group_memberships(group_id, created_at desc);

drop trigger if exists trg_users_updated_at on public.users;
create trigger trg_users_updated_at
before update on public.users
for each row execute function public.set_updated_at();

drop trigger if exists trg_logs_updated_at on public.logs;
create trigger trg_logs_updated_at
before update on public.logs
for each row execute function public.set_updated_at();

drop trigger if exists trg_schedules_updated_at on public.schedules;
create trigger trg_schedules_updated_at
before update on public.schedules
for each row execute function public.set_updated_at();

drop trigger if exists trg_motion_sessions_updated_at on public.motion_sessions;
create trigger trg_motion_sessions_updated_at
before update on public.motion_sessions
for each row execute function public.set_updated_at();

drop trigger if exists trg_recovery_sessions_updated_at on public.recovery_sessions;
create trigger trg_recovery_sessions_updated_at
before update on public.recovery_sessions
for each row execute function public.set_updated_at();

drop trigger if exists trg_medication_events_updated_at on public.medication_events;
create trigger trg_medication_events_updated_at
before update on public.medication_events
for each row execute function public.set_updated_at();

drop trigger if exists trg_posts_updated_at on public.community_posts;
create trigger trg_posts_updated_at
before update on public.community_posts
for each row execute function public.set_updated_at();

drop trigger if exists trg_comments_updated_at on public.community_comments;
create trigger trg_comments_updated_at
before update on public.community_comments
for each row execute function public.set_updated_at();

drop trigger if exists trg_group_memberships_updated_at on public.community_group_memberships;
create trigger trg_group_memberships_updated_at
before update on public.community_group_memberships
for each row execute function public.set_updated_at();

create or replace function public.increment_post_like(p_post_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only callers who actually liked the post may refresh its counter,
  -- and the counter is derived from like rows so repeated calls cannot
  -- inflate it.
  if not exists (
    select 1
    from public.community_post_likes l
    where l.post_id = p_post_id
      and l.user_id = auth.uid()::text
  ) then
    return;
  end if;

  update public.community_posts
    set likes = (
          select count(*)
          from public.community_post_likes l
          where l.post_id = p_post_id
        ),
        updated_at = timezone('utc', now())
  where id = p_post_id
    and is_hidden = false;
end;
$$;

revoke all on function public.increment_post_like(text) from public;
grant execute on function public.increment_post_like(text) to authenticated;

create or replace function public.refresh_post_like_count(p_post_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Recomputes the counter from like rows (the source of truth), so the
  -- call is idempotent and cannot inflate counts. Used after unlike.
  update public.community_posts
    set likes = (
          select count(*)
          from public.community_post_likes l
          where l.post_id = p_post_id
        ),
        updated_at = timezone('utc', now())
  where id = p_post_id
    and is_hidden = false;
end;
$$;

revoke all on function public.refresh_post_like_count(text) from public;
grant execute on function public.refresh_post_like_count(text) to authenticated;

create table if not exists public.community_post_reports (
  post_id text not null references public.community_posts(id) on delete cascade,
  user_id text not null references public.users(id) on delete cascade,
  reason text,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (post_id, user_id)
);

alter table public.community_post_reports enable row level security;

drop policy if exists post_reports_insert_own on public.community_post_reports;
create policy post_reports_insert_own on public.community_post_reports
  for insert to authenticated
  with check (
    user_id = auth.uid()::text
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists post_reports_select_own on public.community_post_reports;
create policy post_reports_select_own on public.community_post_reports
  for select to authenticated
  using (user_id = auth.uid()::text);

create table if not exists public.community_user_blocks (
  blocker_id text not null references public.users(id) on delete cascade,
  -- Deliberately no FK: a block must survive the blocked account deleting
  -- and re-registering, and must be recordable even if the users row is
  -- already gone. Length-capped below like every other free-text id.
  blocked_id text not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (blocker_id, blocked_id)
);

alter table public.community_user_blocks
  drop constraint if exists user_blocks_length_caps;
alter table public.community_user_blocks add constraint user_blocks_length_caps
  check (length(blocked_id) <= 64);

alter table public.community_user_blocks enable row level security;

drop policy if exists user_blocks_select_own on public.community_user_blocks;
create policy user_blocks_select_own on public.community_user_blocks
  for select to authenticated
  using (blocker_id = public.current_uid());

drop policy if exists user_blocks_insert_own on public.community_user_blocks;
create policy user_blocks_insert_own on public.community_user_blocks
  for insert to authenticated
  with check (blocker_id = public.current_uid());

drop policy if exists user_blocks_delete_own on public.community_user_blocks;
create policy user_blocks_delete_own on public.community_user_blocks
  for delete to authenticated
  using (blocker_id = public.current_uid());

create or replace function public.report_post(p_post_id text, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report_count integer;
  v_recent_reports integer;
begin
  -- Anonymous bootstrap sessions carry the authenticated role but must not
  -- moderate: unlimited free anonymous identities would otherwise let a
  -- script hide any post with three fabricated reports.
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'full account required to report posts';
  end if;

  select count(*) into v_recent_reports
  from public.community_post_reports r
  where r.user_id = auth.uid()::text
    and r.created_at > timezone('utc', now()) - interval '1 hour';
  if v_recent_reports >= 10 then
    raise exception 'report rate limit exceeded';
  end if;

  insert into public.community_post_reports (post_id, user_id, reason)
  values (p_post_id, auth.uid()::text, left(coalesce(p_reason, ''), 500))
  on conflict (post_id, user_id) do nothing;

  select count(*) into v_report_count
  from public.community_post_reports r
  where r.post_id = p_post_id;

  -- Reports are counted from unique reporter rows, so a single user cannot
  -- flood a post into hiding. Three unique reports hide the post pending
  -- review.
  update public.community_posts
    set reports = v_report_count,
        is_flagged = v_report_count >= 1,
        is_hidden = is_hidden or v_report_count >= 3,
        updated_at = timezone('utc', now())
  where id = p_post_id;
end;
$$;

revoke all on function public.report_post(text, text) from public;
grant execute on function public.report_post(text, text) to authenticated;

create table if not exists public.community_comment_reports (
  comment_id text not null references public.community_comments(id)
    on delete cascade,
  user_id text not null references public.users(id) on delete cascade,
  reason text,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (comment_id, user_id)
);

alter table public.community_comment_reports enable row level security;

drop policy if exists comment_reports_insert_own
  on public.community_comment_reports;
create policy comment_reports_insert_own on public.community_comment_reports
  for insert to authenticated
  with check (
    user_id = auth.uid()::text
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

drop policy if exists comment_reports_select_own
  on public.community_comment_reports;
create policy comment_reports_select_own on public.community_comment_reports
  for select to authenticated
  using (user_id = auth.uid()::text);

create or replace function public.report_comment(
  p_comment_id text,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report_count integer;
  v_recent_reports integer;
begin
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'full account required to report comments';
  end if;

  -- Reports of posts and comments share one hourly budget per user.
  select
    (select count(*) from public.community_post_reports r
      where r.user_id = auth.uid()::text
        and r.created_at > timezone('utc', now()) - interval '1 hour')
    + (select count(*) from public.community_comment_reports r
      where r.user_id = auth.uid()::text
        and r.created_at > timezone('utc', now()) - interval '1 hour')
  into v_recent_reports;
  if v_recent_reports >= 10 then
    raise exception 'report rate limit exceeded';
  end if;

  insert into public.community_comment_reports (comment_id, user_id, reason)
  values (p_comment_id, auth.uid()::text, left(coalesce(p_reason, ''), 500))
  on conflict (comment_id, user_id) do nothing;

  select count(*) into v_report_count
  from public.community_comment_reports r
  where r.comment_id = p_comment_id;

  -- Same threshold as posts: three unique reporters hide the comment
  -- pending review.
  update public.community_comments
    set reports = v_report_count,
        is_flagged = is_flagged or v_report_count >= 3,
        updated_at = timezone('utc', now())
  where id = p_comment_id;
end;
$$;

revoke all on function public.report_comment(text, text) from public;
grant execute on function public.report_comment(text, text) to authenticated;

create or replace function public.get_comment_counts(p_post_ids text[])
returns table(post_id text, comment_count bigint)
language sql
security definer
set search_path = public
as $$
  select c.post_id, count(*)::bigint
  from public.community_comments c
  where c.post_id = any(p_post_ids)
    and c.is_flagged = false
    -- Community data is full-account only; security definer bypasses the
    -- table policies, so the anonymous gate must be restated here.
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  group by c.post_id;
$$;

revoke all on function public.get_comment_counts(text[]) from public;
grant execute on function public.get_comment_counts(text[]) to authenticated;

create or replace function public.apply_health_mutations(p_mutations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id text := auth.uid()::text;
  v_mutation jsonb;
  v_mutation_id text;
  v_entity_type text;
  v_entity_id text;
  v_operation text;
  v_payload jsonb;
  v_client_updated_at timestamptz;
  v_acknowledged jsonb := '[]'::jsonb;
  v_rows integer;
  v_owner text;
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  -- Health data may only sync under a real account: anonymous bootstrap
  -- sessions are unconsented and unrecoverable after reinstall.
  if coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Anonymous sessions may not sync health data';
  end if;
  if p_mutations is null or jsonb_typeof(p_mutations) <> 'array' then
    raise exception 'p_mutations must be a JSON array';
  end if;
  if jsonb_array_length(p_mutations) > 500 then
    raise exception 'A maximum of 500 mutations may be applied per batch';
  end if;

  for v_mutation in
    select value from jsonb_array_elements(p_mutations)
  loop
    v_mutation_id := trim(coalesce(v_mutation ->> 'mutation_id', ''));

    -- Per-mutation isolation: EVERYTHING fallible - parsing, validation,
    -- the timestamptz cast, and the writes - runs inside this block. A
    -- malformed element must reject only itself; aborting the batch would
    -- read as a transport failure client-side and wedge sync forever.
    begin
    v_entity_type := trim(coalesce(v_mutation ->> 'entity_type', ''));
    v_entity_id := trim(coalesce(v_mutation ->> 'entity_id', ''));
    v_operation := trim(coalesce(v_mutation ->> 'operation', ''));
    v_payload := coalesce(v_mutation -> 'payload', '{}'::jsonb);
    v_client_updated_at := coalesce(
      nullif(v_mutation ->> 'client_updated_at', '')::timestamptz,
      timezone('utc', now())
    );
    -- A device clock running ahead would otherwise mint timestamps that
    -- out-rank every later legitimate write, including deletions.
    v_client_updated_at := least(
      v_client_updated_at,
      timezone('utc', now()) + interval '5 minutes'
    );

    if v_mutation_id = '' or v_entity_id = '' then
      raise exception 'Mutation and entity ids are required';
    end if;
    if v_entity_type not in (
      'log',
      'schedule',
      'recoverySession',
      'medicationEvent',
      'motionSession'
    ) then
      raise exception 'Unsupported entity type: %', v_entity_type;
    end if;
    if v_operation not in ('upsert', 'delete') then
      raise exception 'Unsupported mutation operation: %', v_operation;
    end if;

    if v_operation = 'delete' then
      insert into public.sync_tombstones (
        entity_type,
        entity_id,
        user_id,
        deleted_at,
        mutation_id
      ) values (
        v_entity_type,
        v_entity_id,
        v_user_id,
        v_client_updated_at,
        v_mutation_id
      )
      on conflict (entity_type, entity_id, user_id) do update
        set deleted_at = excluded.deleted_at,
            mutation_id = excluded.mutation_id
      where (public.sync_tombstones.deleted_at,
             public.sync_tombstones.mutation_id)
            <= (excluded.deleted_at, excluded.mutation_id);

      if exists (
        select 1
        from public.sync_tombstones tombstone
        where tombstone.entity_type = v_entity_type
          and tombstone.entity_id = v_entity_id
          and tombstone.user_id = v_user_id
          and tombstone.mutation_id = v_mutation_id
      ) then
        if v_entity_type = 'log' then
          delete from public.logs
          where id = v_entity_id
            and user_id = v_user_id
            and (client_updated_at, last_mutation_id)
                <= (v_client_updated_at, v_mutation_id);
        elsif v_entity_type = 'schedule' then
          delete from public.schedules
          where id = v_entity_id
            and user_id = v_user_id
            and (client_updated_at, last_mutation_id)
                <= (v_client_updated_at, v_mutation_id);
        elsif v_entity_type = 'recoverySession' then
          delete from public.recovery_sessions
          where id = v_entity_id
            and user_id = v_user_id
            and (client_updated_at, last_mutation_id)
                <= (v_client_updated_at, v_mutation_id);
        elsif v_entity_type = 'medicationEvent' then
          delete from public.medication_events
          where id = v_entity_id
            and user_id = v_user_id
            and (client_updated_at, last_mutation_id)
                <= (v_client_updated_at, v_mutation_id);
        elsif v_entity_type = 'motionSession' then
          delete from public.motion_sessions
          where id = v_entity_id
            and user_id = v_user_id
            and (client_updated_at, last_mutation_id)
                <= (v_client_updated_at, v_mutation_id);
        end if;
      end if;
    elsif not exists (
      select 1
      from public.sync_tombstones tombstone
      where tombstone.entity_type = v_entity_type
        and tombstone.entity_id = v_entity_id
        and tombstone.user_id = v_user_id
        and (tombstone.deleted_at, tombstone.mutation_id)
            > (v_client_updated_at, v_mutation_id)
    ) then
      delete from public.sync_tombstones
      where entity_type = v_entity_type
        and entity_id = v_entity_id
        and user_id = v_user_id
        and (deleted_at, mutation_id)
            <= (v_client_updated_at, v_mutation_id);

      if v_entity_type = 'log' then
        insert into public.logs (
          id,
          user_id,
          title,
          data,
          event_time,
          symptom,
          severity,
          client_updated_at,
          last_mutation_id
        ) values (
          v_entity_id,
          v_user_id,
          coalesce(v_payload ->> 'symptom', ''),
          v_payload::text,
          v_payload ->> 'time',
          v_payload ->> 'symptom',
          v_payload ->> 'severity',
          v_client_updated_at,
          v_mutation_id
        )
        on conflict (id) do update
          set title = excluded.title,
              data = excluded.data,
              event_time = excluded.event_time,
              symptom = excluded.symptom,
              severity = excluded.severity,
              client_updated_at = excluded.client_updated_at,
              last_mutation_id = excluded.last_mutation_id
        where public.logs.user_id = v_user_id
          and (public.logs.client_updated_at, public.logs.last_mutation_id)
              <= (excluded.client_updated_at, excluded.last_mutation_id);
      elsif v_entity_type = 'schedule' then
        insert into public.schedules (
          id,
          user_id,
          title,
          data,
          details,
          days,
          client_updated_at,
          last_mutation_id
        ) values (
          v_entity_id,
          v_user_id,
          coalesce(v_payload ->> 'name', ''),
          v_payload::text,
          v_payload ->> 'details',
          v_payload ->> 'days',
          v_client_updated_at,
          v_mutation_id
        )
        on conflict (id) do update
          set title = excluded.title,
              data = excluded.data,
              details = excluded.details,
              days = excluded.days,
              client_updated_at = excluded.client_updated_at,
              last_mutation_id = excluded.last_mutation_id
        where public.schedules.user_id = v_user_id
          and (public.schedules.client_updated_at,
               public.schedules.last_mutation_id)
              <= (excluded.client_updated_at, excluded.last_mutation_id);
      elsif v_entity_type = 'recoverySession' then
        insert into public.recovery_sessions (
          id,
          user_id,
          type,
          video_id,
          title,
          completed_at,
          client_updated_at,
          last_mutation_id
        ) values (
          v_entity_id,
          v_user_id,
          v_payload ->> 'type',
          v_payload ->> 'video_id',
          v_payload ->> 'title',
          coalesce(
            nullif(v_payload ->> 'completed_at', '')::timestamptz,
            v_client_updated_at
          ),
          v_client_updated_at,
          v_mutation_id
        )
        on conflict (id) do update
          set type = excluded.type,
              video_id = excluded.video_id,
              title = excluded.title,
              completed_at = excluded.completed_at,
              client_updated_at = excluded.client_updated_at,
              last_mutation_id = excluded.last_mutation_id
        where public.recovery_sessions.user_id = v_user_id
          and (public.recovery_sessions.client_updated_at,
               public.recovery_sessions.last_mutation_id)
              <= (excluded.client_updated_at, excluded.last_mutation_id);
      elsif v_entity_type = 'medicationEvent' then
        insert into public.medication_events (
          id,
          user_id,
          schedule_id,
          medication_name,
          scheduled_at,
          taken_at,
          status,
          client_updated_at,
          last_mutation_id
        ) values (
          v_entity_id,
          v_user_id,
          nullif(v_payload ->> 'schedule_id', ''),
          coalesce(v_payload ->> 'medication_name', ''),
          coalesce(
            nullif(v_payload ->> 'scheduled_at', '')::timestamptz,
            v_client_updated_at
          ),
          nullif(v_payload ->> 'taken_at', '')::timestamptz,
          coalesce(nullif(v_payload ->> 'status', ''), 'scheduled'),
          v_client_updated_at,
          v_mutation_id
        )
        on conflict (id) do update
          set schedule_id = excluded.schedule_id,
              medication_name = excluded.medication_name,
              scheduled_at = excluded.scheduled_at,
              taken_at = excluded.taken_at,
              status = excluded.status,
              client_updated_at = excluded.client_updated_at,
              last_mutation_id = excluded.last_mutation_id
        where public.medication_events.user_id = v_user_id
          and (public.medication_events.client_updated_at,
               public.medication_events.last_mutation_id)
              <= (excluded.client_updated_at, excluded.last_mutation_id);
      elsif v_entity_type = 'motionSession' then
        insert into public.motion_sessions (
          id,
          user_id,
          routine_id,
          routine_name,
          engine_version,
          completed_at,
          overall_score,
          record,
          evaluation,
          client_updated_at,
          last_mutation_id
        ) values (
          v_entity_id,
          v_user_id,
          coalesce(v_payload ->> 'routine_id', ''),
          coalesce(v_payload ->> 'routine_name', ''),
          coalesce(v_payload ->> 'engine_version', ''),
          coalesce(
            nullif(v_payload ->> 'completed_at', '')::timestamptz,
            v_client_updated_at
          ),
          (v_payload ->> 'overall_score')::double precision,
          coalesce(v_payload -> 'record', '{}'::jsonb),
          coalesce(v_payload -> 'evaluation', '{}'::jsonb),
          v_client_updated_at,
          v_mutation_id
        )
        on conflict (id) do update
          set routine_id = excluded.routine_id,
              routine_name = excluded.routine_name,
              engine_version = excluded.engine_version,
              completed_at = excluded.completed_at,
              overall_score = excluded.overall_score,
              record = excluded.record,
              -- Backup restores replay records without their evidence
              -- documents; an empty evaluation must never erase a stored one.
              evaluation = case
                when excluded.evaluation = '{}'::jsonb
                  then public.motion_sessions.evaluation
                else excluded.evaluation
              end,
              client_updated_at = excluded.client_updated_at,
              last_mutation_id = excluded.last_mutation_id
        where public.motion_sessions.user_id = v_user_id
          and (public.motion_sessions.client_updated_at,
               public.motion_sessions.last_mutation_id)
              <= (excluded.client_updated_at, excluded.last_mutation_id);
      end if;

      -- A zero-row guarded upsert is fine when our own newer row won LWW,
      -- but if the id is owned by ANOTHER account the write was dropped
      -- outright. Acknowledging it would purge the client journal and
      -- lose the record silently; leaving it unacknowledged keeps the
      -- loss visible as a pending change on the device.
      get diagnostics v_rows = row_count;
      if v_rows = 0 then
        v_owner := null;
        if v_entity_type = 'log' then
          select user_id into v_owner
          from public.logs where id = v_entity_id;
        elsif v_entity_type = 'schedule' then
          select user_id into v_owner
          from public.schedules where id = v_entity_id;
        elsif v_entity_type = 'recoverySession' then
          select user_id into v_owner
          from public.recovery_sessions where id = v_entity_id;
        elsif v_entity_type = 'medicationEvent' then
          select user_id into v_owner
          from public.medication_events where id = v_entity_id;
        elsif v_entity_type = 'motionSession' then
          select user_id into v_owner
          from public.motion_sessions where id = v_entity_id;
        end if;
        if v_owner is not null and v_owner <> v_user_id then
          continue;
        end if;
      end if;
    end if;

    v_acknowledged := v_acknowledged || jsonb_build_array(v_mutation_id);
    exception
      -- Any single-mutation failure (constraint, FK from a deleted user
      -- row, tombstone uniqueness) rejects only that mutation; aborting
      -- the batch would wedge every other pending change behind it.
      when others then
        -- Log the id and error class only: sqlerrm can embed row values
        -- (symptom text, medication names) and Postgres logs are not a
        -- place for health data.
        raise warning 'mutation % rejected (sqlstate %)',
          v_mutation_id, sqlstate;
    end;
  end loop;

  return v_acknowledged;
end;
$$;

revoke all on function public.apply_health_mutations(jsonb) from public;
grant execute on function public.apply_health_mutations(jsonb) to authenticated;

alter table public.users enable row level security;
alter table public.logs enable row level security;
alter table public.schedules enable row level security;
alter table public.recovery_sessions enable row level security;
alter table public.medication_events enable row level security;
alter table public.sync_tombstones enable row level security;
alter table public.community_posts enable row level security;
alter table public.community_comments enable row level security;
alter table public.community_post_likes enable row level security;
alter table public.community_group_memberships enable row level security;

drop policy if exists bootstrap_users_all on public.users;
drop policy if exists bootstrap_logs_all on public.logs;
drop policy if exists bootstrap_schedules_all on public.schedules;
drop policy if exists bootstrap_recovery_sessions_all on public.recovery_sessions;
drop policy if exists bootstrap_medication_events_all on public.medication_events;
drop policy if exists bootstrap_sync_tombstones_all on public.sync_tombstones;
drop policy if exists bootstrap_posts_all on public.community_posts;
drop policy if exists bootstrap_comments_all on public.community_comments;
drop policy if exists bootstrap_post_likes_all on public.community_post_likes;
drop policy if exists bootstrap_group_memberships_all on public.community_group_memberships;

drop policy if exists users_select_own on public.users;
drop policy if exists users_insert_own on public.users;
drop policy if exists users_update_own on public.users;
drop policy if exists users_delete_own on public.users;

create policy users_select_own on public.users
  for select to authenticated
  using (id = public.current_uid());

create policy users_insert_own on public.users
  for insert to authenticated
  with check (id = public.current_uid());

create policy users_update_own on public.users
  for update to authenticated
  using (id = public.current_uid())
  with check (id = public.current_uid());

create policy users_delete_own on public.users
  for delete to authenticated
  using (id = public.current_uid());

drop policy if exists logs_select_own on public.logs;
drop policy if exists logs_insert_own on public.logs;
drop policy if exists logs_update_own on public.logs;
drop policy if exists logs_delete_own on public.logs;

create policy logs_select_own on public.logs
  for select to authenticated
  using (user_id = public.current_uid() and public.is_full_account());

create policy logs_insert_own on public.logs
  for insert to authenticated
  with check (user_id = public.current_uid() and public.is_full_account());

create policy logs_update_own on public.logs
  for update to authenticated
  using (user_id = public.current_uid() and public.is_full_account())
  with check (user_id = public.current_uid() and public.is_full_account());

create policy logs_delete_own on public.logs
  for delete to authenticated
  using (user_id = public.current_uid() and public.is_full_account());

drop policy if exists schedules_select_own on public.schedules;
drop policy if exists schedules_insert_own on public.schedules;
drop policy if exists schedules_update_own on public.schedules;
drop policy if exists schedules_delete_own on public.schedules;

create policy schedules_select_own on public.schedules
  for select to authenticated
  using (user_id = public.current_uid() and public.is_full_account());

create policy schedules_insert_own on public.schedules
  for insert to authenticated
  with check (user_id = public.current_uid() and public.is_full_account());

create policy schedules_update_own on public.schedules
  for update to authenticated
  using (user_id = public.current_uid() and public.is_full_account())
  with check (user_id = public.current_uid() and public.is_full_account());

create policy schedules_delete_own on public.schedules
  for delete to authenticated
  using (user_id = public.current_uid() and public.is_full_account());

drop policy if exists recovery_sessions_select_own on public.recovery_sessions;
drop policy if exists recovery_sessions_insert_own on public.recovery_sessions;
drop policy if exists recovery_sessions_update_own on public.recovery_sessions;
drop policy if exists recovery_sessions_delete_own on public.recovery_sessions;

create policy recovery_sessions_select_own on public.recovery_sessions
  for select to authenticated
  using (user_id = public.current_uid() and public.is_full_account());

create policy recovery_sessions_insert_own on public.recovery_sessions
  for insert to authenticated
  with check (
    user_id = public.current_uid()
    and public.is_full_account()
    and length(trim(video_id)) > 0
    and length(trim(title)) > 0
  );

create policy recovery_sessions_update_own on public.recovery_sessions
  for update to authenticated
  using (user_id = public.current_uid() and public.is_full_account())
  with check (user_id = public.current_uid() and public.is_full_account());

create policy recovery_sessions_delete_own on public.recovery_sessions
  for delete to authenticated
  using (user_id = public.current_uid() and public.is_full_account());

alter table public.motion_sessions enable row level security;

drop policy if exists motion_sessions_select_own on public.motion_sessions;
drop policy if exists motion_sessions_insert_own on public.motion_sessions;
drop policy if exists motion_sessions_update_own on public.motion_sessions;
drop policy if exists motion_sessions_delete_own on public.motion_sessions;

create policy motion_sessions_select_own on public.motion_sessions
  for select to authenticated
  using (user_id = public.current_uid() and public.is_full_account());

create policy motion_sessions_insert_own on public.motion_sessions
  for insert to authenticated
  with check (
    user_id = public.current_uid()
    and public.is_full_account()
    and length(trim(routine_id)) > 0
  );

create policy motion_sessions_update_own on public.motion_sessions
  for update to authenticated
  using (user_id = public.current_uid() and public.is_full_account())
  with check (user_id = public.current_uid() and public.is_full_account());

create policy motion_sessions_delete_own on public.motion_sessions
  for delete to authenticated
  using (user_id = public.current_uid() and public.is_full_account());

drop policy if exists medication_events_select_own on public.medication_events;
drop policy if exists medication_events_insert_own on public.medication_events;
drop policy if exists medication_events_update_own on public.medication_events;
drop policy if exists medication_events_delete_own on public.medication_events;

create policy medication_events_select_own on public.medication_events
  for select to authenticated
  using (user_id = public.current_uid() and public.is_full_account());

create policy medication_events_insert_own on public.medication_events
  for insert to authenticated
  with check (
    user_id = public.current_uid()
    and public.is_full_account()
    and length(trim(medication_name)) > 0
  );

create policy medication_events_update_own on public.medication_events
  for update to authenticated
  using (user_id = public.current_uid() and public.is_full_account())
  with check (user_id = public.current_uid() and public.is_full_account());

create policy medication_events_delete_own on public.medication_events
  for delete to authenticated
  using (user_id = public.current_uid() and public.is_full_account());

drop policy if exists sync_tombstones_select_own on public.sync_tombstones;

create policy sync_tombstones_select_own on public.sync_tombstones
  for select to authenticated
  using (user_id = public.current_uid() and public.is_full_account());

drop policy if exists posts_select_all on public.community_posts;
drop policy if exists posts_insert_own on public.community_posts;
drop policy if exists posts_update_own on public.community_posts;
drop policy if exists posts_delete_own on public.community_posts;

-- Anonymous bootstrap sessions must not read member health disclosures;
-- the feed is for full accounts only.
create policy posts_select_all on public.community_posts
  for select to authenticated
  using (
    -- Authors keep sight of their own hidden posts; without the exception
    -- a moderated post silently vanishes for the person who wrote it.
    (is_hidden = false or user_id = public.current_uid())
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

create policy posts_insert_own on public.community_posts
  for insert to authenticated
  with check (
    user_id = public.current_uid()
    and length(trim(content)) > 0
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

-- Server-side content guard: the client-side moderation pass can be
-- Append-only write audit powering the community rate limits. Rows are
-- never removed by user actions (deleting a post does not refund quota)
-- and are pruned opportunistically after 25 hours.
create table if not exists public.community_write_audit (
  id bigint generated always as identity primary key,
  user_id text not null,
  kind text not null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_write_audit_user_kind_created
  on public.community_write_audit (user_id, kind, created_at desc);
create index if not exists idx_write_audit_created
  on public.community_write_audit (created_at);

alter table public.community_write_audit enable row level security;
-- No policies: only the security definer trigger touches this table.

-- bypassed by any REST client holding the anon key, so the length cap and
-- rate limit are enforced here too.
create or replace function public.enforce_community_content()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recent integer;
begin
  if length(trim(new.content)) = 0 or length(new.content) > 2000 then
    raise exception 'content length out of bounds';
  end if;

  if tg_op = 'INSERT' then
    -- Count from the append-only audit, not live rows: counting live rows
    -- lets post-delete-repost cycles bypass the hourly limit entirely.
    select count(*) into v_recent
    from public.community_write_audit a
    where a.user_id = new.user_id
      and a.kind = tg_table_name
      and a.created_at > timezone('utc', now()) - interval '1 hour';
    -- Posts match the client-side product rule (10/hour); comments allow
    -- more because replying in a support thread is higher-frequency.
    if tg_table_name = 'community_comments' then
      if v_recent >= 30 then
        raise exception 'rate limit exceeded';
      end if;
    elsif v_recent >= 10 then
      raise exception 'rate limit exceeded';
    end if;

    insert into public.community_write_audit (user_id, kind)
    values (new.user_id, tg_table_name);
    -- Opportunistic pruning keeps the audit tiny without a scheduled job.
    delete from public.community_write_audit
    where created_at < timezone('utc', now()) - interval '25 hours';
  end if;

  return new;
end;
$$;

create or replace function public.enforce_community_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Display identity hardening: names are capped and non-empty, and the
  -- avatar may only reference a bundled app asset, never an arbitrary URL
  -- or device path delivered by a modified client.
  new.user_name := left(trim(coalesce(new.user_name, '')), 40);
  -- Identity may only be the caller's own profile name or an alias the
  -- caller owns. A never-seen Member-NNNNNN alias is reserved for the
  -- caller on first use; someone else's reserved alias is replaced with
  -- the caller's own (or a neutral label), killing alias impersonation.
  declare
    v_own_name text;
    v_own_alias text;
    v_alias_owner text;
  begin
    select u.name, u.community_alias into v_own_name, v_own_alias
    from public.users u
    where u.id = public.current_uid();

    if new.user_name = '' then
      new.user_name := coalesce(v_own_alias, 'Member');
    elsif new.user_name ~*
      '(parkiwell|admin|moderator|official|staff|support|helpline|doctor|nurse|neurolog|therapist|clinic)'
      or new.user_name ~* '\mdr\M\.?'
    then
      -- Authority-figure and staff impersonation is the top abuse vector
      -- in a patient community; profile names containing these terms are
      -- never shown as community identity, even if they match users.name.
      new.user_name := coalesce(v_own_alias, 'Member');
    elsif new.user_name is not distinct from v_own_name then
      null; -- posting under own profile name
    elsif new.user_name ~ '^Member-[0-9]{4,6}$' then
      if new.user_name is not distinct from v_own_alias then
        null; -- caller's own reserved alias
      else
        select u.id into v_alias_owner
        from public.users u
        where u.community_alias = new.user_name;
        if v_alias_owner is null and v_own_alias is null then
          begin
            update public.users
              set community_alias = new.user_name
              where id = public.current_uid();
          exception
            -- Two devices can race for the same fresh alias; losing the
            -- unique index must not fail the whole post insert.
            when unique_violation then
              new.user_name := 'Member';
          end;
        else
          new.user_name := coalesce(v_own_alias, 'Member');
        end if;
      end if;
    else
      new.user_name := coalesce(v_own_alias, 'Member');
    end if;
  end;
  if new.profile_image is not null
     and new.profile_image not like 'images/%' then
    new.profile_image := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_posts_identity_guard on public.community_posts;
create trigger trg_posts_identity_guard
before insert or update of user_name, profile_image
on public.community_posts
for each row execute function public.enforce_community_identity();

drop trigger if exists trg_comments_identity_guard on public.community_comments;
create trigger trg_comments_identity_guard
before insert or update of user_name, profile_image
on public.community_comments
for each row execute function public.enforce_community_identity();

-- Guard both insert and update: without the update trigger, benign content
-- could be inserted and then rewritten to arbitrary text.
drop trigger if exists trg_posts_content_guard on public.community_posts;
create trigger trg_posts_content_guard
before insert or update of content on public.community_posts
for each row execute function public.enforce_community_content();

drop trigger if exists trg_comments_content_guard on public.community_comments;
create trigger trg_comments_content_guard
before insert or update of content on public.community_comments
for each row execute function public.enforce_community_content();

-- Moderation state is not author-writable: without the column grants an
-- author could clear is_hidden/is_flagged/reports on their own row and
-- undo the community's reports.
revoke update on public.community_posts from authenticated;
-- likes moves only through the security definer RPCs, so an author can
-- never hand-edit their own counter.
grant update (content, category, updated_at)
  on public.community_posts to authenticated;
revoke update on public.community_comments from authenticated;
grant update (content, updated_at)
  on public.community_comments to authenticated;

create policy posts_update_own on public.community_posts
  for update to authenticated
  using (user_id = public.current_uid())
  with check (
    user_id = public.current_uid()
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

create policy posts_delete_own on public.community_posts
  for delete to authenticated
  using (user_id = public.current_uid());

drop policy if exists comments_select_all on public.community_comments;
drop policy if exists comments_insert_own on public.community_comments;
drop policy if exists comments_update_own on public.community_comments;
drop policy if exists comments_delete_own on public.community_comments;

create policy comments_select_all on public.community_comments
  for select to authenticated
  using (
    -- Authors keep sight of their own hidden comments, mirroring posts;
    -- otherwise three reports make a comment vanish for its writer with
    -- no explanation.
    (is_flagged = false or user_id = public.current_uid())
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

create policy comments_insert_own on public.community_comments
  for insert to authenticated
  with check (
    user_id = public.current_uid()
    and length(trim(content)) > 0
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

create policy comments_update_own on public.community_comments
  for update to authenticated
  using (user_id = public.current_uid())
  with check (
    user_id = public.current_uid()
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

create policy comments_delete_own on public.community_comments
  for delete to authenticated
  using (user_id = public.current_uid());

drop policy if exists post_likes_select_own on public.community_post_likes;
drop policy if exists post_likes_insert_own on public.community_post_likes;
drop policy if exists post_likes_delete_own on public.community_post_likes;

create policy post_likes_select_own on public.community_post_likes
  for select to authenticated
  using (user_id = public.current_uid());

create policy post_likes_insert_own on public.community_post_likes
  for insert to authenticated
  with check (
    user_id = public.current_uid()
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

create policy post_likes_delete_own on public.community_post_likes
  for delete to authenticated
  using (user_id = public.current_uid());

drop policy if exists group_memberships_select_own on public.community_group_memberships;
drop policy if exists group_memberships_insert_own on public.community_group_memberships;
drop policy if exists group_memberships_update_own on public.community_group_memberships;
drop policy if exists group_memberships_delete_own on public.community_group_memberships;

create policy group_memberships_select_own on public.community_group_memberships
  for select to authenticated
  using (user_id = public.current_uid());

create policy group_memberships_insert_own on public.community_group_memberships
  for insert to authenticated
  with check (user_id = public.current_uid());

create policy group_memberships_update_own on public.community_group_memberships
  for update to authenticated
  using (user_id = public.current_uid())
  with check (user_id = public.current_uid());

create policy group_memberships_delete_own on public.community_group_memberships
  for delete to authenticated
  using (user_id = public.current_uid());
