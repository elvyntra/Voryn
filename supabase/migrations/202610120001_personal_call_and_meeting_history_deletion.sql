-- Migration: 202610120001_personal_call_and_meeting_history_deletion.sql
-- Checkpoint VORYN-RUNTIME-FIX-3: Part D - Personal Call & Meeting History Deletion
-- Allows users to hide/delete personal call and meeting history items without destroying canonical shared rows.

-- 1. Table for personal hidden calls
create table if not exists public.call_user_hidden_calls (
  user_uid uuid not null references auth.users(id) on delete cascade,
  call_id uuid not null references public.calls(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (user_uid, call_id)
);

create index if not exists call_user_hidden_calls_user_idx
  on public.call_user_hidden_calls (user_uid);

alter table public.call_user_hidden_calls enable row level security;

drop policy if exists "Users can select their own hidden calls" on public.call_user_hidden_calls;
create policy "Users can select their own hidden calls"
  on public.call_user_hidden_calls
  for select
  using (user_uid = auth.uid());

revoke insert, update, delete on public.call_user_hidden_calls from authenticated;
grant select on public.call_user_hidden_calls to authenticated;

-- 2. Table for personal hidden meetings
create table if not exists public.meeting_user_hidden_meetings (
  user_uid uuid not null references auth.users(id) on delete cascade,
  meeting_id uuid not null references public.meetings(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (user_uid, meeting_id)
);

create index if not exists meeting_user_hidden_meetings_user_idx
  on public.meeting_user_hidden_meetings (user_uid);

alter table public.meeting_user_hidden_meetings enable row level security;

drop policy if exists "Users can select their own hidden meetings" on public.meeting_user_hidden_meetings;
create policy "Users can select their own hidden meetings"
  on public.meeting_user_hidden_meetings
  for select
  using (user_uid = auth.uid());

revoke insert, update, delete on public.meeting_user_hidden_meetings from authenticated;
grant select on public.meeting_user_hidden_meetings to authenticated;

-- 3. Functions for call history deletion
create or replace function public.delete_call_history_item(p_call_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return false;
  end if;

  insert into public.call_user_hidden_calls (user_uid, call_id, hidden_at)
  values (v_uid, p_call_id, now())
  on conflict (user_uid, call_id) do nothing;

  return true;
end;
$$;

revoke all on function public.delete_call_history_item(uuid) from public;
grant execute on function public.delete_call_history_item(uuid) to authenticated;

create or replace function public.clear_my_call_history()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_count int := 0;
begin
  if v_uid is null then
    return 0;
  end if;

  insert into public.call_user_hidden_calls (user_uid, call_id, hidden_at)
  select distinct v_uid, cp.call_id, now()
  from public.call_participants cp
  where cp.user_uid = v_uid
  on conflict (user_uid, call_id) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.clear_my_call_history() from public;
grant execute on function public.clear_my_call_history() to authenticated;

-- 4. Functions for meeting history deletion
create or replace function public.delete_meeting_history_item(p_meeting_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return false;
  end if;

  insert into public.meeting_user_hidden_meetings (user_uid, meeting_id, hidden_at)
  values (v_uid, p_meeting_id, now())
  on conflict (user_uid, meeting_id) do nothing;

  return true;
end;
$$;

revoke all on function public.delete_meeting_history_item(uuid) from public;
grant execute on function public.delete_meeting_history_item(uuid) to authenticated;

create or replace function public.clear_my_past_meetings()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_count int := 0;
begin
  if v_uid is null then
    return 0;
  end if;

  insert into public.meeting_user_hidden_meetings (user_uid, meeting_id, hidden_at)
  select distinct v_uid, mp.meeting_id, now()
  from public.meeting_participants mp
  join public.meetings m on m.id = mp.meeting_id
  where mp.user_uid = v_uid
    and (m.status in ('ended', 'cancelled'))
  on conflict (user_uid, meeting_id) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.clear_my_past_meetings() from public;
grant execute on function public.clear_my_past_meetings() to authenticated;

-- 5. Updated list_my_recent_calls filtering out hidden calls
create or replace function public.list_my_recent_calls()
returns table (
  id uuid,
  other_uid uuid,
  display_name text,
  voryn_id text,
  call_type text,
  direction text,
  status text,
  created_at timestamptz,
  answered_at timestamptz,
  ended_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return;
  end if;

  return query
  select distinct on (c.id)
    c.id,
    coalesce(other.user_uid, c.initiated_by) as other_uid,
    coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.voryn_id), ''), 'Voryn User') as display_name,
    coalesce(p.voryn_id, '') as voryn_id,
    c.call_type,
    case when c.initiated_by = auth.uid() then 'outgoing'::text else 'incoming'::text end as direction,
    c.status,
    c.created_at,
    c.answered_at,
    c.ended_at
  from public.calls c
  join public.call_participants mine on mine.call_id = c.id and mine.user_uid = auth.uid()
  left join public.call_participants other on other.call_id = c.id and other.user_uid <> auth.uid()
  left join public.profiles p on p.uid = other.user_uid
  where not exists (
    select 1 from public.call_user_hidden_calls uhc
    where uhc.call_id = c.id and uhc.user_uid = auth.uid()
  )
  order by c.id, c.created_at desc;
end;
$$;

revoke all on function public.list_my_recent_calls() from public;
grant execute on function public.list_my_recent_calls() to authenticated;

-- 6. Updated list_my_meetings filtering out hidden meetings
drop function if exists public.list_my_meetings();

create or replace function public.list_my_meetings()
returns table (
  id uuid,
  title text,
  join_code text,
  access text,
  status text,
  participant_count bigint,
  historical_attendee_count bigint,
  active_participant_count bigint,
  created_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  duration_seconds int,
  host_uid uuid,
  is_host boolean,
  host_name text,
  host_avatar_url text,
  my_role text,
  my_joined_at timestamptz,
  my_invited_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    m.id,
    m.title,
    m.join_code,
    m.access,
    m.status,
    count(distinct mp_all.user_uid) filter (where mp_all.joined_at is not null) as participant_count,
    count(distinct mp_all.user_uid) filter (where mp_all.joined_at is not null) as historical_attendee_count,
    count(distinct mp_all.user_uid) filter (where mp_all.joined_at is not null and mp_all.left_at is null) as active_participant_count,
    m.created_at,
    m.started_at,
    m.ended_at,
    case
      when m.started_at is not null then
        extract(epoch from (coalesce(m.ended_at, now()) - m.started_at))::int
      else null
    end as duration_seconds,
    m.host_uid,
    (m.host_uid = (select auth.uid())) as is_host,
    coalesce(nullif(trim(hp.full_name), ''), 'Host') as host_name,
    hp.avatar_url as host_avatar_url,
    mine.role as my_role,
    mine.joined_at as my_joined_at,
    mine.invited_at as my_invited_at
  from public.meetings m
  join public.meeting_participants mine on mine.meeting_id = m.id and mine.user_uid = (select auth.uid())
  left join public.meeting_participants mp_all on mp_all.meeting_id = m.id
  left join public.profiles hp on hp.uid = m.host_uid
  where not exists (
    select 1 from public.meeting_user_hidden_meetings uhm
    where uhm.meeting_id = m.id and uhm.user_uid = (select auth.uid())
  )
  group by m.id, hp.full_name, hp.avatar_url, mine.role, mine.joined_at, mine.invited_at
  order by m.created_at desc
  limit 100;
$$;

revoke all on function public.list_my_meetings() from public;
grant execute on function public.list_my_meetings() to authenticated;

