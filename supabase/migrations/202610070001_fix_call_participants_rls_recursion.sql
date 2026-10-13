-- 202610070001_fix_call_participants_rls_recursion.sql
-- Fix infinite recursion in public.call_participants and public.calls RLS select policies.

-- Create a SECURITY DEFINER helper function to check call participation
-- without triggering RLS recursively on public.call_participants.
create or replace function public.is_call_participant(
  p_call_id uuid,
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
    from public.call_participants
    where call_id = p_call_id and user_uid = p_user_id
  );
$$;

revoke all on function public.is_call_participant(uuid, uuid) from public;
grant execute on function public.is_call_participant(uuid, uuid) to authenticated;

-- Update calls_participant_select to allow call initiator OR any verified call participant
drop policy if exists "calls_participant_select" on public.calls;
create policy "calls_participant_select" on public.calls
  for select to authenticated
  using (
    initiated_by = (select auth.uid())
    or public.is_call_participant(id, (select auth.uid()))
  );

-- Update call_participants_select to allow user to view their own rows or rows in calls they participate in
drop policy if exists "call_participants_select" on public.call_participants;
create policy "call_participants_select" on public.call_participants
  for select to authenticated
  using (
    user_uid = (select auth.uid())
    or public.is_call_participant(call_id, (select auth.uid()))
  );
