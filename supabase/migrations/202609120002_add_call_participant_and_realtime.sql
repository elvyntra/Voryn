-- 202609120002_add_call_participant_and_realtime.sql
-- Add participant RPC, participant-scoped SELECT policy on calls, and Realtime publication.

create or replace function public.add_call_participant(call_uuid uuid, candidate text)
returns table (user_uid uuid, voryn_id text, full_name text)
language plpgsql security definer set search_path = '' as $$
declare
  caller_id uuid := auth.uid();
  target_id uuid;
  target_voryn text;
  target_name text;
begin
  if caller_id is null then
    raise exception 'Authentication required';
  end if;

  -- Verify caller is an active participant in this call
  if not exists (
    select 1 from public.call_participants
    where call_id = call_uuid and user_uid = caller_id
  ) then
    raise exception 'You are not in this call';
  end if;

  -- Verify the call is still active
  if not exists (
    select 1 from public.calls
    where id = call_uuid and status in ('calling', 'ringing', 'connected')
  ) then
    raise exception 'Call is no longer active';
  end if;

  -- Resolve target candidate from profiles
  select p.uid, p.voryn_id, p.full_name
  into target_id, target_voryn, target_name
  from public.profiles p
  where lower(p.voryn_id) = lower(trim(leading '@' from candidate));

  if target_id is null then
    raise exception 'User not found';
  end if;

  if target_id = caller_id then
    raise exception 'Cannot invite yourself';
  end if;

  -- Check if already participant
  if exists (
    select 1 from public.call_participants
    where call_id = call_uuid and user_uid = target_id
  ) then
    raise exception 'User is already in this call';
  end if;

  -- Check user blocks
  if exists (
    select 1 from public.user_blocks b
    where (b.owner_uid = caller_id and b.blocked_uid = target_id)
       or (b.owner_uid = target_id and b.blocked_uid = caller_id)
  ) then
    raise exception 'Cannot invite this user';
  end if;

  -- Add participant
  insert into public.call_participants (call_id, user_uid)
  values (call_uuid, target_id)
  on conflict (call_id, user_uid) do nothing;

  return query select target_id, target_voryn, target_name;
end;
$$;

revoke all on function public.add_call_participant(uuid, text) from public;
grant execute on function public.add_call_participant(uuid, text) to authenticated;

-- Participant-scoped select on calls for Supabase Realtime Postgres CDC
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

-- Enable publication on calls for realtime CDC
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'calls'
    ) then
      alter publication supabase_realtime add table public.calls;
    end if;
  end if;
end $$;
