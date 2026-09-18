-- Migration: 202609120007_get_my_pending_incoming_call
-- Description: Hardened authenticated RPC to retrieve pending incoming ringing call for open-app recovery

create or replace function public.get_my_pending_incoming_call()
returns table (
  id uuid,
  other_uid uuid,
  display_name text,
  voryn_id text,
  call_type text,
  direction text,
  status text,
  created_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select c.id,
         caller.uid as other_uid,
         caller.full_name as display_name,
         caller.voryn_id,
         c.call_type,
         'incoming'::text as direction,
         c.status,
         c.created_at
  from public.calls c
  join public.call_participants mine on mine.call_id = c.id
       and mine.user_uid = auth.uid()
       and mine.left_at is null
  join public.profiles caller on caller.uid = c.initiated_by
  where c.initiated_by <> auth.uid()
    and c.status in ('calling', 'ringing')
  order by c.created_at desc
  limit 1;
$$;

revoke all on function public.get_my_pending_incoming_call() from public;
grant execute on function public.get_my_pending_incoming_call() to authenticated;
