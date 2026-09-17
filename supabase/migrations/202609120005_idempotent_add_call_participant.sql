-- 202609120005_idempotent_add_call_participant.sql
-- Makes public.add_call_participant idempotent so rapid or duplicate invites
-- safely return success without throwing exceptions.

create or replace function public.add_call_participant(
  call_uuid uuid,
  target_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  target_voryn text;
  target_name text;
  call_rec record;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  if target_user_id is null then
    raise exception 'Target user ID is required';
  end if;

  if target_user_id = caller_id then
    raise exception 'Cannot invite yourself to the call';
  end if;

  -- 1. Verify caller is currently a participant in this call
  if not exists (
    select 1 from public.call_participants
    where call_id = call_uuid and user_uid = caller_id
  ) then
    raise exception 'You are not an active participant in this call';
  end if;

  -- 2. Verify call exists and is in an active state
  select id, status, call_type into call_rec
  from public.calls
  where id = call_uuid;

  if not found then
    raise exception 'Call not found';
  end if;

  if call_rec.status not in ('calling', 'ringing', 'connected') then
    raise exception 'Call is no longer active';
  end if;

  -- 3. Verify target user exists and get profile info
  select p.voryn_id, p.full_name
  into target_voryn, target_name
  from public.profiles p
  where p.uid = target_user_id;

  if not found then
    raise exception 'Target user profile not found';
  end if;

  -- 4. If target is already in the call, return success idempotently
  if exists (
    select 1 from public.call_participants
    where call_id = call_uuid and user_uid = target_user_id
  ) then
    return jsonb_build_object(
      'success', true,
      'already_invited', true,
      'call_id', call_uuid,
      'user_uid', target_user_id,
      'voryn_id', target_voryn,
      'full_name', target_name
    );
  end if;

  -- 5. Enforce user block rules
  if exists (
    select 1 from public.user_blocks b
    where (b.owner_uid = caller_id and b.blocked_uid = target_user_id)
       or (b.owner_uid = target_user_id and b.blocked_uid = caller_id)
  ) then
    raise exception 'Cannot invite this user';
  end if;

  -- 6. Insert new participant
  insert into public.call_participants (
    call_id,
    user_uid,
    muted,
    camera_enabled,
    joined_at
  ) values (
    call_uuid,
    target_user_id,
    false,
    case when call_rec.call_type = 'video' then true else false end,
    null
  )
  on conflict (call_id, user_uid) do nothing;

  return jsonb_build_object(
    'success', true,
    'call_id', call_uuid,
    'user_uid', target_user_id,
    'voryn_id', target_voryn,
    'full_name', target_name
  );
end;
$$;

revoke all on function public.add_call_participant(uuid, uuid) from public;
grant execute on function public.add_call_participant(uuid, uuid) to authenticated;
