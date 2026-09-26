-- Migration: 202609260001_call_waiting_and_hold
-- Description: Call Waiting, Hold & Accept, Atomic Switch, Row Locking, and Capacity Serialization

-- 1. Extend calls status check constraint to include 'on_hold'
alter table public.calls drop constraint if exists calls_status_check;
alter table public.calls add constraint calls_status_check
  check (status in ('calling', 'ringing', 'connected', 'on_hold', 'completed', 'missed', 'declined', 'failed', 'cancelled'));

-- 2. Add held_by column to track which participant placed the call on hold
alter table public.calls add column if not exists held_by uuid references auth.users(id) on delete set null;

-- 3. Atomic Hold & Accept Transaction with deterministic row locking & idempotency
create or replace function public.hold_and_accept_waiting_call(
  p_active_call_id uuid,
  p_waiting_call_id uuid
)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user_uid uuid := auth.uid();
  v_active_call public.calls%rowtype;
  v_waiting_call public.calls%rowtype;
begin
  if v_user_uid is null then raise exception 'Authentication required'; end if;
  if p_active_call_id is null or p_waiting_call_id is null then
    raise exception 'Call IDs cannot be null';
  end if;
  if p_active_call_id = p_waiting_call_id then
    raise exception 'Active and waiting call IDs must be distinct';
  end if;

  -- Deterministic row locking by call UUID to prevent deadlocks across concurrent requests
  perform 1
  from public.calls
  where id in (p_active_call_id, p_waiting_call_id)
  order by id
  for update;

  select * into v_active_call from public.calls where id = p_active_call_id;
  select * into v_waiting_call from public.calls where id = p_waiting_call_id;

  if v_active_call.id is null or v_waiting_call.id is null then
    return jsonb_build_object('result', 'rejected', 'reason', 'call_not_found');
  end if;

  -- Idempotency check: if duplicate action already completed transition, return canonical state
  if v_active_call.status = 'on_hold' and v_active_call.held_by = v_user_uid and v_waiting_call.status = 'connected' then
    return jsonb_build_object(
      'result', 'already_applied',
      'active_call_id', p_waiting_call_id,
      'held_call_id', p_active_call_id
    );
  end if;

  -- Validate participant authority on active call
  if not exists (
    select 1 from public.call_participants p
    where p.call_id = p_active_call_id and p.user_uid = v_user_uid and p.left_at is null
  ) or v_active_call.status <> 'connected' then
    return jsonb_build_object('result', 'rejected', 'reason', 'active_call_not_connected');
  end if;

  -- Validate waiting call: must be ringing AND auth user must be the intended CALLEE (not caller)
  if v_waiting_call.initiated_by = v_user_uid then
    return jsonb_build_object('result', 'rejected', 'reason', 'caller_cannot_accept_own_call');
  end if;

  if not exists (
    select 1 from public.call_participants p
    where p.call_id = p_waiting_call_id and p.user_uid = v_user_uid and p.left_at is null
  ) or v_waiting_call.status not in ('calling', 'ringing') then
    return jsonb_build_object('result', 'rejected', 'reason', 'waiting_call_not_ringing');
  end if;

  -- Capacity check: user must not already have another held call
  if exists (
    select 1 from public.calls c
    join public.call_participants p on p.call_id = c.id
    where p.user_uid = v_user_uid and p.left_at is null and c.status = 'on_hold' and c.id <> p_active_call_id
  ) then
    return jsonb_build_object('result', 'rejected', 'reason', 'capacity_exceeded_held_call_exists');
  end if;

  -- Canonical Atomic Transition
  update public.calls
  set status = 'on_hold', held_by = v_user_uid
  where id = p_active_call_id;

  update public.calls
  set status = 'connected',
      answered_at = coalesce(answered_at, now())
  where id = p_waiting_call_id;

  update public.call_participants
  set joined_at = coalesce(joined_at, now())
  where call_id = p_waiting_call_id and user_uid = v_user_uid;

  return jsonb_build_object(
    'result', 'applied',
    'active_call_id', p_waiting_call_id,
    'held_call_id', p_active_call_id
  );
end;
$$;

revoke all on function public.hold_and_accept_waiting_call(uuid, uuid) from public;
grant execute on function public.hold_and_accept_waiting_call(uuid, uuid) to authenticated;

-- 4. Atomic Switch Transaction with deterministic row locking & idempotency
create or replace function public.switch_held_call(
  p_current_active_call_id uuid,
  p_current_held_call_id uuid
)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user_uid uuid := auth.uid();
  v_active_call public.calls%rowtype;
  v_held_call public.calls%rowtype;
begin
  if v_user_uid is null then raise exception 'Authentication required'; end if;
  if p_current_active_call_id is null or p_current_held_call_id is null then
    raise exception 'Call IDs cannot be null';
  end if;
  if p_current_active_call_id = p_current_held_call_id then
    raise exception 'Active and held call IDs must be distinct';
  end if;

  -- Deterministic row locking
  perform 1
  from public.calls
  where id in (p_current_active_call_id, p_current_held_call_id)
  order by id
  for update;

  select * into v_active_call from public.calls where id = p_current_active_call_id;
  select * into v_held_call from public.calls where id = p_current_held_call_id;

  if v_active_call.id is null or v_held_call.id is null then
    return jsonb_build_object('result', 'rejected', 'reason', 'call_not_found');
  end if;

  -- Idempotency check: if already swapped, return canonical state
  if v_active_call.status = 'on_hold' and v_active_call.held_by = v_user_uid and v_held_call.status = 'connected' then
    return jsonb_build_object(
      'result', 'already_applied',
      'active_call_id', p_current_held_call_id,
      'held_call_id', p_current_active_call_id
    );
  end if;

  -- Verify active is connected
  if v_active_call.status <> 'connected' or not exists (
    select 1 from public.call_participants p
    where p.call_id = p_current_active_call_id and p.user_uid = v_user_uid and p.left_at is null
  ) then
    return jsonb_build_object('result', 'rejected', 'reason', 'current_active_not_connected');
  end if;

  -- Verify held is on_hold and was held by current user
  if v_held_call.status <> 'on_hold' or v_held_call.held_by <> v_user_uid or not exists (
    select 1 from public.call_participants p
    where p.call_id = p_current_held_call_id and p.user_uid = v_user_uid and p.left_at is null
  ) then
    return jsonb_build_object('result', 'rejected', 'reason', 'current_held_not_on_hold');
  end if;

  -- Atomic Swap
  update public.calls set status = 'on_hold', held_by = v_user_uid where id = p_current_active_call_id;
  update public.calls set status = 'connected', held_by = null where id = p_current_held_call_id;

  return jsonb_build_object(
    'result', 'applied',
    'active_call_id', p_current_held_call_id,
    'held_call_id', p_current_active_call_id
  );
end;
$$;

revoke all on function public.switch_held_call(uuid, uuid) from public;
grant execute on function public.switch_held_call(uuid, uuid) to authenticated;

-- 5. Secure Standalone Hold / Resume
create or replace function public.set_call_hold_state(call_uuid uuid, is_held boolean)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_user_uid uuid := auth.uid();
  v_call public.calls%rowtype;
begin
  if v_user_uid is null then raise exception 'Authentication required'; end if;

  select * into v_call
  from public.calls
  where id = call_uuid
  for update;

  if v_call.id is null then
    raise exception 'Call not found';
  end if;

  if not exists (
    select 1 from public.call_participants
    where call_id = call_uuid and user_uid = v_user_uid and left_at is null
  ) then
    raise exception 'Not a participant of this call';
  end if;

  if is_held then
    -- Idempotent check
    if v_call.status = 'on_hold' and v_call.held_by = v_user_uid then
      return true;
    end if;
    if v_call.status <> 'connected' then
      raise exception 'Only connected calls can be placed on hold';
    end if;
    update public.calls set status = 'on_hold', held_by = v_user_uid where id = call_uuid;
    return true;
  else
    -- Idempotent check
    if v_call.status = 'connected' then
      return true;
    end if;
    if v_call.status <> 'on_hold' then
      raise exception 'Call is not on hold';
    end if;
    -- Security: Only the participant who put the call on hold can resume it
    if v_call.held_by <> v_user_uid then
      raise exception 'Unauthorized: only the participant who placed this call on hold may resume it';
    end if;
    update public.calls set status = 'connected', held_by = null where id = call_uuid;
    return true;
  end if;
end;
$$;

revoke all on function public.set_call_hold_state(uuid, boolean) from public;
grant execute on function public.set_call_hold_state(uuid, boolean) to authenticated;

-- 6. Update start_direct_call with transaction-scoped target advisory lock and capacity check
create or replace function public.start_direct_call(candidate text, requested_type text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  target_uid uuid;
  target_dnd boolean;
  target_who_can_call text;
  new_call_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if requested_type not in ('audio', 'video') then
    raise exception 'Invalid call type';
  end if;

  -- Match either by Voryn ID or by user UUID
  select uid into target_uid from public.profiles
  where lower(voryn_id) = lower(trim(leading '@' from candidate))
     or uid::text = candidate;

  if target_uid is null or target_uid = auth.uid() then
    raise exception 'User not found';
  end if;

  -- Prevent caller from starting an outgoing call if already on a call (Rule 12)
  if (
    select count(*)
    from public.calls c
    join public.call_participants cp on cp.call_id = c.id
    where cp.user_uid = auth.uid()
      and cp.left_at is null
      and c.status in ('calling', 'ringing', 'connected', 'on_hold')
  ) >= 1 then
    raise exception 'already_on_call';
  end if;

  -- 1. Serialize concurrent calls targeting the same user via transaction-scoped advisory lock
  perform pg_advisory_xact_lock(hashtext(target_uid::text));

  -- 2. Enforce bidirectional blocks with privacy-preserving error
  if exists (
    select 1 from public.user_blocks b
    where (b.owner_uid = auth.uid() and b.blocked_uid = target_uid)
       or (b.owner_uid = target_uid and b.blocked_uid = auth.uid())
  ) then
    raise exception 'calling_unavailable';
  end if;

  -- 3. Inspect target user's privacy and DND settings
  select coalesce(s.dnd_enabled, s.do_not_disturb, false),
         coalesce(s.who_can_call, case when s.allow_calls = 'contacts' then 'saved_contacts' else s.allow_calls end, 'everyone')
  into target_dnd, target_who_can_call
  from public.user_settings s
  where s.user_uid = target_uid;

  if target_dnd is true then
    raise exception 'dnd_enabled';
  end if;

  if target_who_can_call = 'nobody' then
    raise exception 'calls_disabled';
  elsif target_who_can_call = 'saved_contacts' then
    if not exists (
      select 1 from public.user_contacts uc
      where uc.owner_uid = target_uid and uc.contact_uid = auth.uid()
    ) then
      raise exception 'contacts_only';
    end if;
  end if;

  -- 4. Server-Side Capacity Check: Max 2 non-terminal calls per target user (1 active + 1 waiting/held)
  if (
    select count(*)
    from public.calls c
    join public.call_participants cp on cp.call_id = c.id
    where cp.user_uid = target_uid
      and cp.left_at is null
      and c.status in ('calling', 'ringing', 'connected', 'on_hold')
  ) >= 2 then
    raise exception 'user_busy';
  end if;

  -- Create call record
  insert into public.calls (initiated_by, call_type, status)
  values (auth.uid(), requested_type, 'calling')
  returning id into new_call_id;

  insert into public.call_participants (call_id, user_uid)
  values (new_call_id, auth.uid()), (new_call_id, target_uid);

  return new_call_id;
end;
$$;

revoke all on function public.start_direct_call(text, text) from public;
grant execute on function public.start_direct_call(text, text) to authenticated;
