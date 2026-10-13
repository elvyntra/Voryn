-- 202610090001_meeting_participants_and_invitations.sql
-- Checkpoint MEET-4B: Meeting Contact Invitations & Participant Discovery

-- 1. Helper RPC to list authorized meeting participants with privacy preservation
create or replace function public.list_meeting_participants(p_meeting_id uuid)
returns table (
  meeting_id uuid,
  user_uid uuid,
  role text,
  display_name text,
  avatar_url text,
  invited_at timestamptz,
  joined_at timestamptz,
  left_at timestamptz,
  is_active boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    mp.meeting_id,
    mp.user_uid,
    mp.role,
    coalesce(nullif(trim(p.full_name), ''), p.voryn_id, 'Participant') as display_name,
    p.avatar_url,
    mp.invited_at,
    mp.joined_at,
    mp.left_at,
    (mp.joined_at is not null and mp.left_at is null) as is_active
  from public.meeting_participants mp
  join public.meetings m on m.id = mp.meeting_id
  left join public.profiles p on p.uid = mp.user_uid
  where mp.meeting_id = p_meeting_id
    and (
      m.host_uid = (select auth.uid())
      or exists (
        select 1 from public.meeting_participants me
        where me.meeting_id = p_meeting_id and me.user_uid = (select auth.uid())
      )
    )
  order by
    case when mp.role = 'host' then 0 else 1 end,
    case when mp.joined_at is not null and mp.left_at is null then 0
         when mp.invited_at is not null and mp.joined_at is null then 1
         else 2 end,
    coalesce(mp.joined_at, mp.invited_at) asc;
$$;

revoke all on function public.list_meeting_participants(uuid) from public;
grant execute on function public.list_meeting_participants(uuid) to authenticated;

-- 2. Update list_my_meetings to expose my_role, my_joined_at, and my_invited_at
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
  group by m.id, hp.full_name, hp.avatar_url, mine.role, mine.joined_at, mine.invited_at
  order by m.created_at desc
  limit 100;
$$;

revoke all on function public.list_my_meetings() from public;
grant execute on function public.list_my_meetings() to authenticated;

-- 3. Update resolve_meeting_for_prejoin to respect invited-only meeting boundary
create or replace function public.resolve_meeting_for_prejoin(candidate_code text)
returns table (
  meeting_id uuid,
  title text,
  status text,
  access text,
  host_name text,
  host_avatar_url text,
  active_participant_count bigint,
  capacity int
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_norm_code text;
  v_meeting_row public.meetings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if candidate_code is null then
    return;
  end if;

  v_norm_code := lower(trim(candidate_code));

  -- Normalize unhyphenated 9-char codes to xxx-xxx-xxx
  if v_norm_code ~ '^[0-9a-z]{9}$' then
    v_norm_code := substr(v_norm_code, 1, 3) || '-' ||
                   substr(v_norm_code, 4, 3) || '-' ||
                   substr(v_norm_code, 7, 3);
  end if;

  -- Strict format check: exactly 3-3-3 pattern
  if v_norm_code !~ '^[0-9a-z]{3}-[0-9a-z]{3}-[0-9a-z]{3}$' then
    return;
  end if;

  -- Reject ended/cancelled meetings; only ready or active permitted
  select * into v_meeting_row
  from public.meetings m
  where m.join_code = v_norm_code and m.status in ('ready', 'active');

  if v_meeting_row.id is null then
    return;
  end if;

  -- Invited-only boundary: caller must be host or invited participant
  if v_meeting_row.access = 'invited' and v_meeting_row.host_uid <> auth.uid() and not exists (
    select 1
    from public.meeting_participants mp
    where mp.meeting_id = v_meeting_row.id and mp.user_uid = auth.uid()
  ) then
    return;
  end if;

  return query
  select
    v_meeting_row.id as meeting_id,
    v_meeting_row.title,
    v_meeting_row.status,
    v_meeting_row.access,
    coalesce(nullif(trim(p.full_name), ''), 'Host') as host_name,
    p.avatar_url as host_avatar_url,
    (
      select count(*)
      from public.meeting_participants mp
      where mp.meeting_id = v_meeting_row.id
        and mp.joined_at is not null
        and mp.left_at is null
    ) as active_participant_count,
    8 as capacity
  from public.profiles p
  where p.uid = v_meeting_row.host_uid;

  if not found then
    return query
    select
      v_meeting_row.id as meeting_id,
      v_meeting_row.title,
      v_meeting_row.status,
      v_meeting_row.access,
      'Host'::text as host_name,
      null::text as host_avatar_url,
      (
        select count(*)
        from public.meeting_participants mp
        where mp.meeting_id = v_meeting_row.id
          and mp.joined_at is not null
          and mp.left_at is null
      ) as active_participant_count,
      8 as capacity;
  end if;
end;
$$;

revoke all on function public.resolve_meeting_for_prejoin(text) from public;
grant execute on function public.resolve_meeting_for_prejoin(text) to authenticated;

-- 4. Enable Supabase Realtime for meetings and meeting_participants
alter table public.meetings replica identity full;
alter table public.meeting_participants replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'meetings'
    ) then
      alter publication supabase_realtime add table public.meetings;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'meeting_participants'
    ) then
      alter publication supabase_realtime add table public.meeting_participants;
    end if;
  end if;
end $$;

