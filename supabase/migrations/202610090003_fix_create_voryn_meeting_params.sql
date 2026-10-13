-- Migration: 202610090003_fix_create_voryn_meeting_params.sql
-- Checkpoint VORYN-FIX-1: Support dual parameter signatures and return livekit_room_name

-- Drop text, text signature if present to avoid overload ambiguity
drop function if exists public.create_voryn_meeting(text, text);

create or replace function public.create_voryn_meeting(
  meeting_title text default null,
  meeting_access text default null,
  p_title text default null,
  p_access text default null
)
returns table (
  id uuid,
  title text,
  join_code text,
  access text,
  status text,
  created_at timestamptz,
  livekit_room_name text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text;
  v_access text;
  new_id uuid;
  new_code text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  v_title := coalesce(meeting_title, p_title);
  v_access := coalesce(meeting_access, p_access, 'link');

  if v_title is null or char_length(trim(v_title)) not between 1 and 60 then
    raise exception 'Invalid meeting title';
  end if;

  if v_access not in ('link', 'invited') then
    raise exception 'Invalid meeting access';
  end if;

  loop
    new_code := public.generate_meeting_join_code();
    exit when not exists (select 1 from public.meetings m where m.join_code = new_code);
  end loop;

  insert into public.meetings as created (host_uid, title, join_code, access, status)
  values (auth.uid(), trim(v_title), new_code, v_access, 'ready')
  returning created.id into new_id;

  -- Host participant row inserted with role 'host', joined_at NULL (consistent with pre-join architecture)
  insert into public.meeting_participants (meeting_id, user_uid, role, joined_at)
  values (new_id, auth.uid(), 'host', null)
  on conflict (meeting_id, user_uid) do update
  set role = 'host';

  return query
  select
    m.id,
    m.title,
    m.join_code,
    m.access,
    m.status,
    m.created_at,
    ('voryn-meeting-' || m.id::text)::text as livekit_room_name
  from public.meetings m
  where m.id = new_id;
end;
$$;

revoke all on function public.create_voryn_meeting(text, text, text, text) from public;
grant execute on function public.create_voryn_meeting(text, text, text, text) to authenticated;

