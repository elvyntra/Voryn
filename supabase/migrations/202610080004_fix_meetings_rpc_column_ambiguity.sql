-- 202610080004_fix_meetings_rpc_column_ambiguity.sql
-- Checkpoint MEET-2A.1: Forward-only corrective migration to disambiguate PL/pgSQL column references

CREATE OR REPLACE FUNCTION public.resolve_meeting_for_prejoin(candidate_code text)
 RETURNS TABLE(meeting_id uuid, title text, status text, access text, host_name text, host_avatar_url text, active_participant_count bigint, capacity integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;
revoke all on function public.resolve_meeting_for_prejoin(text) from public;
grant execute on function public.resolve_meeting_for_prejoin(text) to authenticated;

CREATE OR REPLACE FUNCTION public.start_voryn_meeting(p_meeting_id uuid)
 RETURNS TABLE(id uuid, title text, join_code text, access text, status text, started_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_meeting public.meetings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_meeting
  from public.meetings m
  where m.id = p_meeting_id
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
    set status = 'active', started_at = coalesce(public.meetings.started_at, now())
    where public.meetings.id = p_meeting_id
    returning * into v_meeting;
  end if;

  return query
  select v_meeting.id, v_meeting.title, v_meeting.join_code, v_meeting.access, v_meeting.status, v_meeting.started_at;
end;
$function$;
revoke all on function public.start_voryn_meeting(uuid) from public;
grant execute on function public.start_voryn_meeting(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.leave_voryn_meeting(p_meeting_id uuid)
 RETURNS TABLE(meeting_id uuid, status text, active_participant_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_meeting public.meetings%rowtype;
  v_active_count bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_meeting
  from public.meetings m
  where m.id = p_meeting_id
  for update;

  if v_meeting.id is null then
    raise exception 'Meeting not found';
  end if;

  if not exists (
    select 1
    from public.meeting_participants mp
    where mp.meeting_id = p_meeting_id and mp.user_uid = auth.uid()
  ) then
    raise exception 'Participant not found in meeting';
  end if;

  -- Set own left_at = now() idempotently
  update public.meeting_participants
  set left_at = coalesce(left_at, now())
  where public.meeting_participants.meeting_id = p_meeting_id and public.meeting_participants.user_uid = auth.uid();

  -- Transactionally count remaining active participants
  select count(*) into v_active_count
  from public.meeting_participants mp
  where mp.meeting_id = p_meeting_id
    and mp.joined_at is not null
    and mp.left_at is null;

  -- Atomically auto-end meeting if active and remaining active participants becomes 0
  if v_meeting.status = 'active' and v_active_count = 0 then
    update public.meetings
    set status = 'ended', ended_at = coalesce(public.meetings.ended_at, now())
    where public.meetings.id = p_meeting_id
    returning * into v_meeting;
  end if;

  return query
  select v_meeting.id, v_meeting.status, v_active_count;
end;
$function$;
revoke all on function public.leave_voryn_meeting(uuid) from public;
grant execute on function public.leave_voryn_meeting(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.end_voryn_meeting_for_everyone(p_meeting_id uuid)
 RETURNS TABLE(id uuid, status text, ended_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_meeting public.meetings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_meeting
  from public.meetings m
  where m.id = p_meeting_id
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
  set status = 'ended', ended_at = coalesce(public.meetings.ended_at, now())
  where public.meetings.id = p_meeting_id
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
$function$;
revoke all on function public.end_voryn_meeting_for_everyone(uuid) from public;
grant execute on function public.end_voryn_meeting_for_everyone(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.cancel_voryn_meeting(p_meeting_id uuid)
 RETURNS TABLE(id uuid, status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_meeting public.meetings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_meeting
  from public.meetings m
  where m.id = p_meeting_id
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
  set status = 'cancelled', ended_at = coalesce(public.meetings.ended_at, now())
  where public.meetings.id = p_meeting_id
  returning * into v_meeting;

  return query
  select v_meeting.id, v_meeting.status;
end;
$function$;
revoke all on function public.cancel_voryn_meeting(uuid) from public;
grant execute on function public.cancel_voryn_meeting(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.invite_meeting_participant(p_meeting_id uuid, p_target_user_id uuid)
 RETURNS TABLE(meeting_id uuid, user_uid uuid, role text, invited_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_meeting public.meetings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_meeting
  from public.meetings m
  where m.id = p_meeting_id;

  if v_meeting.id is null then
    raise exception 'Meeting not found';
  end if;

  if v_meeting.status in ('ended', 'cancelled') then
    raise exception 'Cannot invite participants to % meeting', v_meeting.status;
  end if;

  -- Caller must be host or current meeting participant
  if v_meeting.host_uid <> auth.uid() and not exists (
    select 1
    from public.meeting_participants mp
    where mp.meeting_id = p_meeting_id and mp.user_uid = auth.uid()
  ) then
    raise exception 'Unauthorized to invite participants to this meeting';
  end if;

  -- Target user must exist in auth.users
  if not exists (select 1 from auth.users u where u.id = p_target_user_id) then
    raise exception 'Target user does not exist';
  end if;

  -- Idempotently insert invitation; preserve existing role if already host
  insert into public.meeting_participants (meeting_id, user_uid, role, invited_at)
  values (p_meeting_id, p_target_user_id, 'participant', now())
  on conflict on constraint meeting_participants_pkey do update
  set invited_at = coalesce(public.meeting_participants.invited_at, now());

  return query
  select mp.meeting_id, mp.user_uid, mp.role, mp.invited_at
  from public.meeting_participants mp
  where mp.meeting_id = p_meeting_id and mp.user_uid = p_target_user_id;
end;
$function$;
revoke all on function public.invite_meeting_participant(uuid, uuid) from public;
grant execute on function public.invite_meeting_participant(uuid, uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.join_voryn_meeting(candidate_code text)
 RETURNS TABLE(id uuid, title text, join_code text, access text, status text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  from public.meetings m
  where m.join_code = v_norm_code and m.status in ('ready', 'active')
  for update;

  if meeting_row.id is null then
    return;
  end if;

  -- Invited-only check: host or pre-existing invited participant record required
  if meeting_row.access = 'invited' and meeting_row.host_uid <> auth.uid() and not exists (
    select 1
    from public.meeting_participants mp
    where mp.meeting_id = meeting_row.id and mp.user_uid = auth.uid()
  ) then
    return;
  end if;

  -- Capacity check: max 8 active participants
  select count(*) into v_active_count
  from public.meeting_participants mp
  where mp.meeting_id = meeting_row.id
    and mp.joined_at is not null
    and mp.left_at is null;

  select exists (
    select 1
    from public.meeting_participants mp
    where mp.meeting_id = meeting_row.id
      and mp.user_uid = auth.uid()
      and mp.joined_at is not null
      and mp.left_at is null
  ) into v_is_already_active;

  if v_active_count >= 8 and not v_is_already_active then
    raise exception 'Meeting is at maximum capacity (8 participants)';
  end if;

  -- If meeting is ready, first admitted attendee activates it
  if meeting_row.status = 'ready' then
    update public.meetings
    set status = 'active', started_at = coalesce(public.meetings.started_at, now())
    where public.meetings.id = meeting_row.id
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
$function$;
revoke all on function public.join_voryn_meeting(text) from public;
grant execute on function public.join_voryn_meeting(text) to authenticated;
