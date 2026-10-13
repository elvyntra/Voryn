-- Migration: 202610090004_fix_recents_call_history.sql
-- Checkpoint VORYN-FIX-1: Resilient call history retrieval with profile and participant null safety

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
  order by c.id, c.created_at desc;
end;
$$;

revoke all on function public.list_my_recent_calls() from public;
grant execute on function public.list_my_recent_calls() to authenticated;

