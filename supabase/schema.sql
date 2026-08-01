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

create table if not exists public.users (
  id text primary key,
  name text not null default '[Name]',
  email text,
  age integer not null default 0,
  profile_image text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

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
  with check (user_id = auth.uid()::text);

drop policy if exists post_reports_select_own on public.community_post_reports;
create policy post_reports_select_own on public.community_post_reports
  for select to authenticated
  using (user_id = auth.uid()::text);

create or replace function public.report_post(p_post_id text, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report_count integer;
begin
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
begin
  if v_user_id is null then
    raise exception 'Authentication required';
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
    v_entity_type := trim(coalesce(v_mutation ->> 'entity_type', ''));
    v_entity_id := trim(coalesce(v_mutation ->> 'entity_id', ''));
    v_operation := trim(coalesce(v_mutation ->> 'operation', ''));
    v_payload := coalesce(v_mutation -> 'payload', '{}'::jsonb);
    v_client_updated_at := coalesce(
      nullif(v_mutation ->> 'client_updated_at', '')::timestamptz,
      timezone('utc', now())
    );

    if v_mutation_id = '' or v_entity_id = '' then
      raise exception 'Mutation and entity ids are required';
    end if;
    if v_entity_type not in (
      'log',
      'schedule',
      'recoverySession',
      'medicationEvent'
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
      end if;
    end if;

    v_acknowledged := v_acknowledged || jsonb_build_array(v_mutation_id);
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
  using (user_id = public.current_uid());

create policy logs_insert_own on public.logs
  for insert to authenticated
  with check (user_id = public.current_uid());

create policy logs_update_own on public.logs
  for update to authenticated
  using (user_id = public.current_uid())
  with check (user_id = public.current_uid());

create policy logs_delete_own on public.logs
  for delete to authenticated
  using (user_id = public.current_uid());

drop policy if exists schedules_select_own on public.schedules;
drop policy if exists schedules_insert_own on public.schedules;
drop policy if exists schedules_update_own on public.schedules;
drop policy if exists schedules_delete_own on public.schedules;

create policy schedules_select_own on public.schedules
  for select to authenticated
  using (user_id = public.current_uid());

create policy schedules_insert_own on public.schedules
  for insert to authenticated
  with check (user_id = public.current_uid());

create policy schedules_update_own on public.schedules
  for update to authenticated
  using (user_id = public.current_uid())
  with check (user_id = public.current_uid());

create policy schedules_delete_own on public.schedules
  for delete to authenticated
  using (user_id = public.current_uid());

drop policy if exists recovery_sessions_select_own on public.recovery_sessions;
drop policy if exists recovery_sessions_insert_own on public.recovery_sessions;
drop policy if exists recovery_sessions_update_own on public.recovery_sessions;
drop policy if exists recovery_sessions_delete_own on public.recovery_sessions;

create policy recovery_sessions_select_own on public.recovery_sessions
  for select to authenticated
  using (user_id = public.current_uid());

create policy recovery_sessions_insert_own on public.recovery_sessions
  for insert to authenticated
  with check (
    user_id = public.current_uid()
    and length(trim(video_id)) > 0
    and length(trim(title)) > 0
  );

create policy recovery_sessions_update_own on public.recovery_sessions
  for update to authenticated
  using (user_id = public.current_uid())
  with check (user_id = public.current_uid());

create policy recovery_sessions_delete_own on public.recovery_sessions
  for delete to authenticated
  using (user_id = public.current_uid());

drop policy if exists medication_events_select_own on public.medication_events;
drop policy if exists medication_events_insert_own on public.medication_events;
drop policy if exists medication_events_update_own on public.medication_events;
drop policy if exists medication_events_delete_own on public.medication_events;

create policy medication_events_select_own on public.medication_events
  for select to authenticated
  using (user_id = public.current_uid());

create policy medication_events_insert_own on public.medication_events
  for insert to authenticated
  with check (
    user_id = public.current_uid()
    and length(trim(medication_name)) > 0
  );

create policy medication_events_update_own on public.medication_events
  for update to authenticated
  using (user_id = public.current_uid())
  with check (user_id = public.current_uid());

create policy medication_events_delete_own on public.medication_events
  for delete to authenticated
  using (user_id = public.current_uid());

drop policy if exists sync_tombstones_select_own on public.sync_tombstones;

create policy sync_tombstones_select_own on public.sync_tombstones
  for select to authenticated
  using (user_id = public.current_uid());

drop policy if exists posts_select_all on public.community_posts;
drop policy if exists posts_insert_own on public.community_posts;
drop policy if exists posts_update_own on public.community_posts;
drop policy if exists posts_delete_own on public.community_posts;

-- Anonymous bootstrap sessions must not read member health disclosures;
-- the feed is for full accounts only.
create policy posts_select_all on public.community_posts
  for select to authenticated
  using (
    is_hidden = false
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

create policy posts_insert_own on public.community_posts
  for insert to authenticated
  with check (
    user_id = public.current_uid()
    and length(trim(content)) > 0
  );

-- Server-side content guard: the client-side moderation pass can be
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
    if tg_table_name = 'community_comments' then
      select count(*) into v_recent
      from public.community_comments c
      where c.user_id = new.user_id
        and c.created_at > timezone('utc', now()) - interval '1 hour';
    else
      select count(*) into v_recent
      from public.community_posts p
      where p.user_id = new.user_id
        and p.created_at > timezone('utc', now()) - interval '1 hour';
    end if;
    if v_recent >= 30 then
      raise exception 'rate limit exceeded';
    end if;
  end if;

  return new;
end;
$$;

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
grant update (content, category, likes, updated_at)
  on public.community_posts to authenticated;
revoke update on public.community_comments from authenticated;
grant update (content, updated_at)
  on public.community_comments to authenticated;

create policy posts_update_own on public.community_posts
  for update to authenticated
  using (user_id = public.current_uid())
  with check (user_id = public.current_uid());

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
    is_flagged = false
    and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false
  );

create policy comments_insert_own on public.community_comments
  for insert to authenticated
  with check (
    user_id = public.current_uid()
    and length(trim(content)) > 0
  );

create policy comments_update_own on public.community_comments
  for update to authenticated
  using (user_id = public.current_uid())
  with check (user_id = public.current_uid());

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
  with check (user_id = public.current_uid());

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
