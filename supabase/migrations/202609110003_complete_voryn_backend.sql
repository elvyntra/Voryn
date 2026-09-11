-- Voryn backend completion: privacy, presence, devices, calls, meetings,
-- call messages, notifications, reports, and avatar storage.

create extension if not exists pgcrypto;

alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists bio text;
alter table public.profiles add column if not exists presence_status text not null default 'offline';
alter table public.profiles add column if not exists last_seen_at timestamptz;

do $$ begin
  alter table public.profiles add constraint profiles_presence_status_check
    check (presence_status in ('online', 'busy', 'do_not_disturb', 'offline'));
exception when duplicate_object then null;
end $$;

create table if not exists public.user_settings (
  user_uid uuid primary key references auth.users(id) on delete cascade,
  discover_by_voryn_id boolean not null default true,
  discover_by_phone boolean not null default true,
  show_online_status boolean not null default true,
  allow_calls text not null default 'everyone'
    check (allow_calls in ('everyone', 'contacts', 'nobody')),
  incoming_call_notifications boolean not null default true,
  missed_call_notifications boolean not null default true,
  meeting_notifications boolean not null default true,
  vibration boolean not null default true,
  sound boolean not null default true,
  microphone_on_join boolean not null default true,
  camera_on_join boolean not null default false,
  low_data_calls boolean not null default false,
  do_not_disturb boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_uid uuid not null references auth.users(id) on delete cascade,
  installation_id text not null,
  platform text not null check (platform in ('android', 'ios', 'web', 'windows', 'macos', 'linux')),
  device_name text,
  push_token text,
  last_active_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_uid, installation_id)
);

create table if not exists public.calls (
  id uuid primary key default gen_random_uuid(),
  initiated_by uuid not null references auth.users(id) on delete cascade,
  call_type text not null check (call_type in ('audio', 'video')),
  status text not null default 'calling'
    check (status in ('calling', 'ringing', 'connected', 'completed', 'missed', 'declined', 'failed', 'cancelled')),
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz,
  ended_reason text
);

create table if not exists public.call_participants (
  call_id uuid not null references public.calls(id) on delete cascade,
  user_uid uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz,
  left_at timestamptz,
  muted boolean not null default false,
  camera_enabled boolean not null default false,
  primary key (call_id, user_uid)
);

create table if not exists public.meetings (
  id uuid primary key default gen_random_uuid(),
  host_uid uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 60),
  join_code text not null unique,
  access text not null default 'link'
    check (access in ('link', 'invited')),
  status text not null default 'ready'
    check (status in ('ready', 'active', 'ended', 'cancelled')),
  scheduled_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.meeting_participants (
  meeting_id uuid not null references public.meetings(id) on delete cascade,
  user_uid uuid not null references auth.users(id) on delete cascade,
  role text not null default 'participant' check (role in ('host', 'participant')),
  invited_at timestamptz,
  joined_at timestamptz,
  left_at timestamptz,
  primary key (meeting_id, user_uid)
);

create table if not exists public.call_messages (
  id uuid primary key default gen_random_uuid(),
  sender_uid uuid not null references auth.users(id) on delete cascade,
  recipient_uid uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 120),
  remind_to_call boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  check (sender_uid <> recipient_uid)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_uid uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  title text not null,
  body text,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_uid uuid not null references auth.users(id) on delete cascade,
  reported_uid uuid not null references auth.users(id) on delete cascade,
  reason text not null,
  details text check (char_length(details) <= 250),
  status text not null default 'open' check (status in ('open', 'reviewing', 'closed')),
  created_at timestamptz not null default now(),
  check (reporter_uid <> reported_uid)
);

create index if not exists calls_created_at_idx on public.calls (created_at desc);
create index if not exists call_participants_user_idx on public.call_participants (user_uid, call_id);
create index if not exists meetings_host_idx on public.meetings (host_uid, created_at desc);
create index if not exists meeting_participants_user_idx on public.meeting_participants (user_uid, meeting_id);
create index if not exists call_messages_recipient_idx on public.call_messages (recipient_uid, created_at desc);
create index if not exists notifications_user_idx on public.notifications (user_uid, created_at desc);

alter table public.user_settings enable row level security;
alter table public.user_devices enable row level security;
alter table public.calls enable row level security;
alter table public.call_participants enable row level security;
alter table public.meetings enable row level security;
alter table public.meeting_participants enable row level security;
alter table public.call_messages enable row level security;
alter table public.notifications enable row level security;
alter table public.user_reports enable row level security;

drop policy if exists "settings_own_rows" on public.user_settings;
create policy "settings_own_rows" on public.user_settings for all to authenticated
  using ((select auth.uid()) = user_uid)
  with check ((select auth.uid()) = user_uid);

drop policy if exists "devices_own_rows" on public.user_devices;
create policy "devices_own_rows" on public.user_devices for all to authenticated
  using ((select auth.uid()) = user_uid)
  with check ((select auth.uid()) = user_uid);

-- Calls and meetings are intentionally RPC-only. Their RLS-enabled tables have
-- no direct client policies, which avoids cross-participant policy recursion.
drop policy if exists "calls_participant_read" on public.calls;
drop policy if exists "call_participants_member_read" on public.call_participants;
drop policy if exists "meetings_member_read" on public.meetings;
drop policy if exists "meeting_participants_member_read" on public.meeting_participants;

drop policy if exists "call_messages_participant_rows" on public.call_messages;
create policy "call_messages_participant_rows" on public.call_messages for all to authenticated
  using ((select auth.uid()) in (sender_uid, recipient_uid))
  with check ((select auth.uid()) = sender_uid);

drop policy if exists "notifications_own_rows" on public.notifications;
create policy "notifications_own_rows" on public.notifications for select to authenticated
  using ((select auth.uid()) = user_uid);

drop policy if exists "reports_insert_own" on public.user_reports;
create policy "reports_insert_own" on public.user_reports for insert to authenticated
  with check ((select auth.uid()) = reporter_uid);

create or replace function public.ensure_voryn_user_defaults()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.user_settings (user_uid) values (new.id) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_voryn_defaults on auth.users;
create trigger on_auth_user_created_voryn_defaults
  after insert on auth.users for each row
  execute procedure public.ensure_voryn_user_defaults();

insert into public.user_settings (user_uid)
select id from auth.users on conflict do nothing;

create or replace function public.find_user_by_phone(normalized_phone text)
returns table (uid uuid, display_name text, voryn_id text, phone text, presence text)
language sql stable security definer set search_path = '' as $$
  select p.uid,
         p.full_name,
         p.voryn_id,
         p.phone,
         case when coalesce(s.show_online_status, true) then p.presence_status else 'offline' end
  from public.profiles p
  left join public.user_settings s on s.user_uid = p.uid
  where regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') =
        regexp_replace(coalesce(normalized_phone, ''), '[^0-9]', '', 'g')
    and auth.uid() is not null
    and coalesce(s.discover_by_phone, true)
    and p.voryn_id is not null
    and p.uid <> auth.uid()
    and not exists (
      select 1 from public.user_blocks b
      where (b.owner_uid = auth.uid() and b.blocked_uid = p.uid)
         or (b.owner_uid = p.uid and b.blocked_uid = auth.uid())
    )
  limit 1;
$$;

create or replace function public.find_user_by_voryn_id(candidate text)
returns table (uid uuid, display_name text, voryn_id text, phone text, presence text)
language sql stable security definer set search_path = '' as $$
  select p.uid,
         p.full_name,
         p.voryn_id,
         null::text,
         case when coalesce(s.show_online_status, true) then p.presence_status else 'offline' end
  from public.profiles p
  left join public.user_settings s on s.user_uid = p.uid
  where lower(p.voryn_id) = lower(trim(leading '@' from candidate))
    and auth.uid() is not null
    and coalesce(s.discover_by_voryn_id, true)
    and p.uid <> auth.uid()
    and not exists (
      select 1 from public.user_blocks b
      where (b.owner_uid = auth.uid() and b.blocked_uid = p.uid)
         or (b.owner_uid = p.uid and b.blocked_uid = auth.uid())
    )
  limit 1;
$$;

create or replace function public.set_my_presence(new_status text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if new_status not in ('online', 'busy', 'do_not_disturb', 'offline') then
    raise exception 'Invalid presence status';
  end if;
  update public.profiles
  set presence_status = new_status, last_seen_at = now(), updated_at = now()
  where uid = auth.uid();
  return found;
end;
$$;

create or replace function public.start_direct_call(candidate text, requested_type text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target_uid uuid; new_call_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if requested_type not in ('audio', 'video') then raise exception 'Invalid call type'; end if;
  select uid into target_uid from public.profiles
  where lower(voryn_id) = lower(trim(leading '@' from candidate));
  if target_uid is null or target_uid = auth.uid() then raise exception 'User not found'; end if;
  if exists (
    select 1 from public.user_blocks b
    where (b.owner_uid = auth.uid() and b.blocked_uid = target_uid)
       or (b.owner_uid = target_uid and b.blocked_uid = auth.uid())
  ) then raise exception 'Calling unavailable'; end if;
  insert into public.calls (initiated_by, call_type) values (auth.uid(), requested_type)
  returning id into new_call_id;
  insert into public.call_participants (call_id, user_uid)
  values (new_call_id, auth.uid()), (new_call_id, target_uid);
  return new_call_id;
end;
$$;

create or replace function public.update_call_state(call_uuid uuid, new_status text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (select 1 from public.call_participants where call_id = call_uuid and user_uid = auth.uid()) then
    raise exception 'Call unavailable';
  end if;
  if new_status not in ('calling', 'ringing', 'connected', 'completed', 'missed', 'declined', 'failed', 'cancelled') then
    raise exception 'Invalid call status';
  end if;
  update public.calls set
    status = new_status,
    answered_at = case when new_status = 'connected' and answered_at is null then now() else answered_at end,
    ended_at = case when new_status in ('completed', 'missed', 'declined', 'failed', 'cancelled') then now() else ended_at end
  where id = call_uuid;
  return found;
end;
$$;

create or replace function public.list_my_recent_calls()
returns table (
  id uuid, other_uid uuid, display_name text, voryn_id text, call_type text,
  direction text, status text, created_at timestamptz, answered_at timestamptz, ended_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select c.id, other.user_uid, p.full_name, p.voryn_id, c.call_type,
         case when c.initiated_by = auth.uid() then 'outgoing' else 'incoming' end,
         c.status, c.created_at, c.answered_at, c.ended_at
  from public.calls c
  join public.call_participants mine on mine.call_id = c.id and mine.user_uid = auth.uid()
  join public.call_participants other on other.call_id = c.id and other.user_uid <> auth.uid()
  join public.profiles p on p.uid = other.user_uid
  order by c.created_at desc
  limit 200;
$$;

create or replace function public.create_voryn_meeting(meeting_title text, meeting_access text default 'link')
returns table (id uuid, title text, join_code text, access text, status text, created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare new_id uuid; new_code text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if char_length(trim(meeting_title)) not between 1 and 60 then raise exception 'Invalid meeting title'; end if;
  if meeting_access not in ('link', 'invited') then raise exception 'Invalid meeting access'; end if;
  loop
    new_code := lower(substr(encode(gen_random_bytes(8), 'hex'), 1, 3) || '-' ||
                      substr(encode(gen_random_bytes(8), 'hex'), 1, 3) || '-' ||
                      substr(encode(gen_random_bytes(8), 'hex'), 1, 3));
    exit when not exists (select 1 from public.meetings m where m.join_code = new_code);
  end loop;
  insert into public.meetings as created (host_uid, title, join_code, access)
  values (auth.uid(), trim(meeting_title), new_code, meeting_access)
  returning created.id into new_id;
  insert into public.meeting_participants (meeting_id, user_uid, role, joined_at)
  values (new_id, auth.uid(), 'host', now());
  return query select m.id, m.title, m.join_code, m.access, m.status, m.created_at
    from public.meetings m where m.id = new_id;
end;
$$;

create or replace function public.join_voryn_meeting(candidate_code text)
returns table (id uuid, title text, join_code text, access text, status text, created_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare meeting_row public.meetings%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into meeting_row from public.meetings
  where join_code = lower(trim(candidate_code)) and status in ('ready', 'active');
  if meeting_row.id is null then return; end if;
  if meeting_row.access = 'invited' and not exists (
    select 1 from public.meeting_participants
    where meeting_id = meeting_row.id and user_uid = auth.uid()
  ) then return; end if;
  insert into public.meeting_participants (meeting_id, user_uid, role, joined_at)
  values (meeting_row.id, auth.uid(), 'participant', now())
  on conflict (meeting_id, user_uid) do update set joined_at = now(), left_at = null;
  return query select meeting_row.id, meeting_row.title, meeting_row.join_code,
    meeting_row.access, meeting_row.status, meeting_row.created_at;
end;
$$;

create or replace function public.list_my_meetings()
returns table (
  id uuid, title text, join_code text, access text, status text,
  participant_count bigint, created_at timestamptz, started_at timestamptz, ended_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select m.id, m.title, m.join_code, m.access, m.status,
         count(mp_all.user_uid), m.created_at, m.started_at, m.ended_at
  from public.meetings m
  join public.meeting_participants mine on mine.meeting_id = m.id and mine.user_uid = auth.uid()
  left join public.meeting_participants mp_all on mp_all.meeting_id = m.id
  group by m.id
  order by m.created_at desc
  limit 100;
$$;

create or replace function public.send_call_message(candidate text, message_body text, remind boolean default false)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target_uid uuid; message_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select uid into target_uid from public.profiles
  where lower(voryn_id) = lower(trim(leading '@' from candidate));
  if target_uid is null or target_uid = auth.uid() then raise exception 'User not found'; end if;
  if char_length(trim(message_body)) not between 1 and 120 then raise exception 'Invalid message'; end if;
  if exists (
    select 1 from public.user_blocks b
    where (b.owner_uid = auth.uid() and b.blocked_uid = target_uid)
       or (b.owner_uid = target_uid and b.blocked_uid = auth.uid())
  ) then raise exception 'Messaging unavailable'; end if;
  insert into public.call_messages (sender_uid, recipient_uid, body, remind_to_call)
  values (auth.uid(), target_uid, trim(message_body), remind)
  returning id into message_id;
  return message_id;
end;
$$;

create or replace function public.list_my_call_messages()
returns table (
  id uuid, sender_uid uuid, sender_name text, sender_voryn_id text,
  body text, remind_to_call boolean, read_at timestamptz, created_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select cm.id, cm.sender_uid, p.full_name, p.voryn_id,
         cm.body, cm.remind_to_call, cm.read_at, cm.created_at
  from public.call_messages cm
  join public.profiles p on p.uid = cm.sender_uid
  where cm.recipient_uid = auth.uid()
  order by cm.created_at desc
  limit 200;
$$;

create or replace function public.mark_call_message_read(message_uuid uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.call_messages set read_at = coalesce(read_at, now())
  where id = message_uuid and recipient_uid = auth.uid();
  return found;
end;
$$;

create or replace function public.submit_user_report(candidate text, report_reason text, report_details text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare target_uid uuid; report_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select uid into target_uid from public.profiles
  where lower(voryn_id) = lower(trim(leading '@' from candidate));
  if target_uid is null or target_uid = auth.uid() then raise exception 'User not found'; end if;
  insert into public.user_reports (reporter_uid, reported_uid, reason, details)
  values (auth.uid(), target_uid, trim(report_reason), nullif(trim(report_details), ''))
  returning id into report_id;
  return report_id;
end;
$$;

revoke all on public.user_settings, public.user_devices, public.calls,
  public.call_participants, public.meetings, public.meeting_participants,
  public.call_messages, public.notifications, public.user_reports from anon;

revoke all on public.calls, public.call_participants, public.meetings,
  public.meeting_participants, public.notifications, public.user_reports from authenticated;

grant select, insert, update, delete on public.user_settings, public.user_devices to authenticated;
grant select, insert, update on public.call_messages to authenticated;

revoke all on function public.find_user_by_phone(text) from public;
revoke all on function public.find_user_by_voryn_id(text) from public;
revoke all on function public.set_my_presence(text) from public;
revoke all on function public.start_direct_call(text, text) from public;
revoke all on function public.update_call_state(uuid, text) from public;
revoke all on function public.list_my_recent_calls() from public;
revoke all on function public.create_voryn_meeting(text, text) from public;
revoke all on function public.join_voryn_meeting(text) from public;
revoke all on function public.list_my_meetings() from public;
revoke all on function public.send_call_message(text, text, boolean) from public;
revoke all on function public.list_my_call_messages() from public;
revoke all on function public.mark_call_message_read(uuid) from public;
revoke all on function public.submit_user_report(text, text, text) from public;

grant execute on function public.find_user_by_phone(text) to authenticated;
grant execute on function public.find_user_by_voryn_id(text) to authenticated;
grant execute on function public.set_my_presence(text) to authenticated;
grant execute on function public.start_direct_call(text, text) to authenticated;
grant execute on function public.update_call_state(uuid, text) to authenticated;
grant execute on function public.list_my_recent_calls() to authenticated;
grant execute on function public.create_voryn_meeting(text, text) to authenticated;
grant execute on function public.join_voryn_meeting(text) to authenticated;
grant execute on function public.list_my_meetings() to authenticated;
grant execute on function public.send_call_message(text, text, boolean) to authenticated;
grant execute on function public.list_my_call_messages() to authenticated;
grant execute on function public.mark_call_message_read(uuid) to authenticated;
grant execute on function public.submit_user_report(text, text, text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read" on storage.objects for select to public
  using (bucket_id = 'avatars');

drop policy if exists "avatars_owner_insert" on storage.objects;
create policy "avatars_owner_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

drop policy if exists "avatars_owner_update" on storage.objects;
create policy "avatars_owner_update" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and owner_id = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and owner_id = (select auth.uid())::text);

drop policy if exists "avatars_owner_delete" on storage.objects;
create policy "avatars_owner_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and owner_id = (select auth.uid())::text);
