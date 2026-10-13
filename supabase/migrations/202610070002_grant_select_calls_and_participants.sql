-- 202610070002_grant_select_calls_and_participants.sql
-- Grant SELECT on calls and call_participants to authenticated role.

grant select on public.calls to authenticated;
grant select on public.call_participants to authenticated;
