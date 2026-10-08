-- 202610080003_meetings_hardening_and_lifecycle.sql
-- Checkpoint MEET-2A: Meetings Database & RPC Hardening

-- 1. Helper functions for recursion-safe RLS
create or replace function public.is_meeting_participant(
  p_meeting_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.meeting_participants
    where meeting_id = p_meeting_id and user_uid = p_user_id
  );
$$;

revoke all on function public.is_meeting_participant(uuid, uuid) from public;
grant execute on function public.is_meeting_participant(uuid, uuid) to authenticated;

create or replace function public.is_meeting_host(
  p_meeting_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.meetings
    where id = p_meeting_id and host_uid = p_user_id
  );
$$;

revoke all on function public.is_meeting_host(uuid, uuid) from public;
grant execute on function public.is_meeting_host(uuid, uuid) to authenticated;

-- 2. RLS & SELECT grants
alter table public.meetings enable row level security;
alter table public.meeting_participants enable row level security;

grant select on public.meetings to authenticated;
grant select on public.meeting_participants to authenticated;

drop policy if exists "meetings_select_policy" on public.meetings;
create policy "meetings_select_policy" on public.meetings
  for select to authenticated
  using (
    host_uid = (select auth.uid())
    or public.is_meeting_participant(id, (select auth.uid()))
  );

drop policy if exists "meeting_participants_select_policy" on public.meeting_participants;
create policy "meeting_participants_select_policy" on public.meeting_participants
  for select to authenticated
  using (
    user_uid = (select auth.uid())
    or public.is_meeting_participant(meeting_id, (select auth.uid()))
    or public.is_meeting_host(meeting_id, (select auth.uid()))
  );

-- 3. Additional performance indexes
create index if not exists meetings_join_code_idx on public.meetings (join_code);
create index if not exists meetings_status_idx on public.meetings (status);
create index if not exists meeting_participants_user_idx on public.meeting_participants (user_uid, meeting_id);

-- 4. Cryptographically secure Base36 join code generator
create or replace function public.generate_meeting_join_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  alphabet text := '0123456789abcdefghijklmnopqrstuvwxyz';
  bytes bytea;
  raw_chars text := '';
  i int;
  b int;
begin
  -- 9 cryptographic base36 characters using rejection sampling (b < 252 ensures zero modulo bias: 252 = 36 * 7)
  while length(raw_chars) < 9 loop
    bytes := extensions.gen_random_bytes(16);
    for i in 0 .. length(bytes) - 1 loop
      b := get_byte(bytes, i);
      if b < 252 and length(raw_chars) < 9 then
        raw_chars := raw_chars || substr(alphabet, (b % 36) + 1, 1);
      end if;
    end loop;
  end loop;

  return substr(raw_chars, 1, 3) || '-' || substr(raw_chars, 4, 3) || '-' || substr(raw_chars, 7, 3);
end;
$$;

revoke all on function public.generate_meeting_join_code() from public;
grant execute on function public.generate_meeting_join_code() to authenticated;

-- 5. Hardened create_voryn_meeting
create or replace function public.create_voryn_meeting(
  meeting_title text,
  meeting_access text default 'link'
)
returns table (
  id uuid,
  title text,
  join_code text,
  access text,
  status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_id uuid;
  new_code text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if char_length(trim(meeting_title)) not between 1 and 60 then
    raise exception 'Invalid meeting title';
  end if;

  if meeting_access not in ('link', 'invited') then
    raise exception 'Invalid meeting access';
  end if;

  loop
    new_code := public.generate_meeting_join_code();
    exit when not exists (select 1 from public.meetings m where m.join_code = new_code);
  end loop;

  insert into public.meetings as created (host_uid, title, join_code, access, status)
  values (auth.uid(), trim(meeting_title), new_code, meeting_access, 'ready')
  returning created.id into new_id;

  -- Host participant row inserted with role 'host', joined_at NULL (consistent with Model B pre-join architecture)
  insert into public.meeting_participants (meeting_id, user_uid, role, joined_at)
  values (new_id, auth.uid(), 'host', null);

  return query
  select m.id, m.title, m.join_code, m.access, m.status, m.created_at
  from public.meetings m
  where m.id = new_id;
end;
$$;

revoke all on function public.create_voryn_meeting(text, text) from public;
grant execute on function public.create_voryn_meeting(text, text) to authenticated;

-- 6. resolve_meeting_for_prejoin
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
  from public.meetings
  where join_code = v_norm_code and status in ('ready', 'active');

  if v_meeting_row.id is null then
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

-- 7. start_voryn_meeting
create or replace function public.start_voryn_meeting(p_meeting_id uuid)
returns table (
  id uuid,
  title text,
  join_code text,
  access text,
  status text,
  started_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meeting public.meetings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_meeting
  from public.meetings
  where id = p_meeting_id
  for update;

  if v_meeting.id is null then
    raise exception 'Meeting not found';
  end if;

  if v_meeting.host_uid <> auth.uid() then
    raise exception 'Only the meeting host can start the meeting';
  end if;

  if v_meeting.status in ('ended', 'cancelled') then
    raise exception 'Meeting has already %', v_meeting.status;
  end if;

  if v_meeting.status = 'ready' then
    update public.meetings
    set status = 'active', started_at = coalesce(started_at, now())
    where id = p_meeting_id
    returning * into v_meeting;
  end if;

  return query
  select v_meeting.id, v_meeting.title, v_meeting.join_code, v_meeting.access, v_meeting.status, v_meeting.started_at;
end;
$$;

revoke all on function public.start_voryn_meeting(uuid) from public;
grant execute on function public.start_voryn_meeting(uuid) to authenticated;

-- 8. leave_voryn_meeting
create or replace function public.leave_voryn_meeting(p_meeting_id uuid)
returns table (
  meeting_id uuid,
  status text,
  active_participant_count bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meeting public.meetings%rowtype;
  v_active_count bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_meeting
  from public.meetings
  where id = p_meeting_id
  for update;

  if v_meeting.id is null then
    raise exception 'Meeting not found';
  end if;

  if not exists (
    select 1
    from public.meeting_participants
    where meeting_id = p_meeting_id and user_uid = auth.uid()
  ) then
    raise exception 'Participant not found in meeting';
  end if;

  -- Set own left_at = now() idempotently
  update public.meeting_participants
  set left_at = coalesce(left_at, now())
  where meeting_id = p_meeting_id and user_uid = auth.uid();

  -- Transactionally count remaining active participants
  select count(*) into v_active_count
  from public.meeting_participants
  where meeting_id = p_meeting_id
    and joined_at is not null
    and left_at is null;

  -- Atomically auto-end meeting if active and remaining active participants becomes 0
  if v_meeting.status = 'active' and v_active_count = 0 then
    update public.meetings
    set status = 'ended', ended_at = coalesce(ended_at, now())
    where id = p_meeting_id
    returning * into v_meeting;
  end if;

  return query
  select v_meeting.id, v_meeting.status, v_active_count;
end;
$$;

revoke all on function public.leave_voryn_meeting(uuid) from public;
grant execute on function public.leave_voryn_meeting(uuid) to authenticated;

-- 9. end_voryn_meeting_for_everyone
create or replace function public.end_voryn_meeting_for_everyone(p_meeting_id uuid)
returns table (
  id uuid,
  status text,
  ended_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meeting public.meetings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_meeting
  from public.meetings
  where id = p_meeting_id
  for update;

  if v_meeting.id is null then
    raise exception 'Meeting not found';
  end if;

  if v_meeting.host_uid <> auth.uid() then
    raise exception 'Only the meeting host can end the meeting for everyone';
  end if;

  if v_meeting.status = 'cancelled' then
    raise exception 'Cancelled meeting cannot be ended';
  end if;

  if v_meeting.status = 'ended' then
    return query select v_meeting.id, v_meeting.status, v_meeting.ended_at;
    return;
  end if;

  update public.meetings
  set status = 'ended', ended_at = coalesce(ended_at, now())
  where id = p_meeting_id
  returning * into v_meeting;

  -- Atomically mark all active participants as left
  update public.meeting_participants
  set left_at = coalesce(left_at, now())
  where meeting_id = p_meeting_id
    and joined_at is not null
    and left_at is null;

  return query
  select v_meeting.id, v_meeting.status, v_meeting.ended_at;
end;
$$;

revoke all on function public.end_voryn_meeting_for_everyone(uuid) from public;
grant execute on function public.end_voryn_meeting_for_everyone(uuid) to authenticated;

-- 10. cancel_voryn_meeting
create or replace function public.cancel_voryn_meeting(p_meeting_id uuid)
returns table (
  id uuid,
  status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meeting public.meetings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_meeting
  from public.meetings
  where id = p_meeting_id
  for update;

  if v_meeting.id is null then
    raise exception 'Meeting not found';
  end if;

  if v_meeting.host_uid <> auth.uid() then
    raise exception 'Only the meeting host can cancel the meeting';
  end if;

  if v_meeting.status = 'cancelled' then
    return query select v_meeting.id, v_meeting.status;
    return;
  end if;

  if v_meeting.status = 'active' then
    raise exception 'Active meeting cannot be cancelled; end it instead';
  end if;

  if v_meeting.status = 'ended' then
    raise exception 'Ended meeting cannot be cancelled';
  end if;

  update public.meetings
  set status = 'cancelled', ended_at = coalesce(ended_at, now())
  where id = p_meeting_id
  returning * into v_meeting;

  return query
  select v_meeting.id, v_meeting.status;
end;
$$;

revoke all on function public.cancel_voryn_meeting(uuid) from public;
grant execute on function public.cancel_voryn_meeting(uuid) to authenticated;

-- 11. invite_meeting_participant
create or replace function public.invite_meeting_participant(
  p_meeting_id uuid,
  p_target_user_id uuid
)
returns table (
  meeting_id uuid,
  user_uid uuid,
  role text,
  invited_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_meeting public.meetings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_meeting
  from public.meetings
  where id = p_meeting_id;

  if v_meeting.id is null then
    raise exception 'Meeting not found';
  end if;

  if v_meeting.status in ('ended', 'cancelled') then
    raise exception 'Cannot invite participants to % meeting', v_meeting.status;
  end if;

  -- Caller must be host or current meeting participant
  if v_meeting.host_uid <> auth.uid() and not exists (
    select 1
    from public.meeting_participants
    where meeting_id = p_meeting_id and user_uid = auth.uid()
  ) then
    raise exception 'Unauthorized to invite participants to this meeting';
  end if;

  -- Target user must exist in auth.users
  if not exists (select 1 from auth.users where id = p_target_user_id) then
    raise exception 'Target user does not exist';
  end if;

  -- Idempotently insert invitation; preserve existing role if already host
  insert into public.meeting_participants (meeting_id, user_uid, role, invited_at)
  values (p_meeting_id, p_target_user_id, 'participant', now())
  on conflict (meeting_id, user_uid) do update
  set invited_at = coalesce(public.meeting_participants.invited_at, now());

  return query
  select mp.meeting_id, mp.user_uid, mp.role, mp.invited_at
  from public.meeting_participants mp
  where mp.meeting_id = p_meeting_id and mp.user_uid = p_target_user_id;
end;
$$;

revoke all on function public.invite_meeting_participant(uuid, uuid) from public;
grant execute on function public.invite_meeting_participant(uuid, uuid) to authenticated;

-- 12. Hardened join_voryn_meeting
create or replace function public.join_voryn_meeting(candidate_code text)
returns table (
  id uuid,
  title text,
  join_code text,
  access text,
  status text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_norm_code text;
  meeting_row public.meetings%rowtype;
  v_active_count bigint;
  v_is_already_active boolean := false;
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if candidate_code is null then
    return;
  end if;

  v_norm_code := lower(trim(candidate_code));

  -- Normalize unhyphenated 9-char codes
  if v_norm_code ~ '^[0-9a-z]{9}$' then
    v_norm_code := substr(v_norm_code, 1, 3) || '-' ||
                   substr(v_norm_code, 4, 3) || '-' ||
                   substr(v_norm_code, 7, 3);
  end if;

  if v_norm_code !~ '^[0-9a-z]{3}-[0-9a-z]{3}-[0-9a-z]{3}$' then
    return;
  end if;

  -- Deterministic row locking
  select * into meeting_row
  from public.meetings
  where join_code = v_norm_code and status in ('ready', 'active')
  for update;

  if meeting_row.id is null then
    return;
  end if;

  -- Invited-only check: host or pre-existing invited participant record required
  if meeting_row.access = 'invited' and meeting_row.host_uid <> auth.uid() and not exists (
    select 1
    from public.meeting_participants
    where meeting_id = meeting_row.id and user_uid = auth.uid()
  ) then
    return;
  end if;

  -- Capacity check: max 8 active participants
  select count(*) into v_active_count
  from public.meeting_participants
  where meeting_id = meeting_row.id
    and joined_at is not null
    and left_at is null;

  select exists (
    select 1
    from public.meeting_participants
    where meeting_id = meeting_row.id
      and user_uid = auth.uid()
      and joined_at is not null
      and left_at is null
  ) into v_is_already_active;

  if v_active_count >= 8 and not v_is_already_active then
    raise exception 'Meeting is at maximum capacity (8 participants)';
  end if;

  -- If meeting is ready, first admitted attendee activates it
  if meeting_row.status = 'ready' then
    update public.meetings
    set status = 'active', started_at = coalesce(started_at, now())
    where id = meeting_row.id
    returning * into meeting_row;
  end if;

  -- Determine role: host role preserved, never downgraded
  v_role := case when meeting_row.host_uid = auth.uid() then 'host' else 'participant' end;

  insert into public.meeting_participants (meeting_id, user_uid, role, joined_at, left_at)
  values (meeting_row.id, auth.uid(), v_role, now(), null)
  on conflict (meeting_id, user_uid) do update set
    joined_at = coalesce(public.meeting_participants.joined_at, now()),
    left_at = null,
    role = case
      when public.meeting_participants.role = 'host' or meeting_row.host_uid = auth.uid() then 'host'
      else 'participant'
    end;

  return query
  select meeting_row.id, meeting_row.title, meeting_row.join_code,
         meeting_row.access, meeting_row.status, meeting_row.created_at;
end;
$$;

revoke all on function public.join_voryn_meeting(text) from public;
grant execute on function public.join_voryn_meeting(text) to authenticated;

-- 13. Upgraded list_my_meetings
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
  is_host boolean,
  host_name text,
  host_avatar_url text
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
    (m.host_uid = auth.uid()) as is_host,
    coalesce(nullif(trim(hp.full_name), ''), 'Host') as host_name,
    hp.avatar_url as host_avatar_url
  from public.meetings m
  join public.meeting_participants mine on mine.meeting_id = m.id and mine.user_uid = auth.uid()
  left join public.meeting_participants mp_all on mp_all.meeting_id = m.id
  left join public.profiles hp on hp.uid = m.host_uid
  group by m.id, hp.full_name, hp.avatar_url
  order by m.created_at desc
  limit 100;
$$;

revoke all on function public.list_my_meetings() from public;
grant execute on function public.list_my_meetings() to authenticated;
