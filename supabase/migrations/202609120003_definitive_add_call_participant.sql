-- 202609120003_definitive_add_call_participant.sql
-- Canonical add_call_participant RPC accepting stable user UUID,
-- participant RLS select policies, and publication to supabase_realtime.

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

  -- 4. Check if target is already in the call
  if exists (
    select 1 from public.call_participants
    where call_id = call_uuid and user_uid = target_user_id
  ) then
    raise exception 'User is already a participant in this call';
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

-- Ensure authenticated participants can query calls and call_participants via RLS
drop policy if exists "calls_participant_select" on public.calls;
create policy "calls_participant_select" on public.calls
  for select to authenticated
  using (
    exists (
      select 1 from public.call_participants cp
      where cp.call_id = id and cp.user_uid = (select auth.uid())
    )
  );

drop policy if exists "call_participants_select" on public.call_participants;
create policy "call_participants_select" on public.call_participants
  for select to authenticated
  using (
    exists (
      select 1 from public.call_participants cp
      where cp.call_id = call_id and cp.user_uid = (select auth.uid())
    )
  );

-- Idempotently add calls and call_participants to supabase_realtime publication
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'calls'
    ) then
      alter publication supabase_realtime add table public.calls;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'call_participants'
    ) then
      alter publication supabase_realtime add table public.call_participants;
    end if;
  end if;
end $$;
