-- Migration: 202609120006_privacy_settings_and_enforcement.sql
-- Privacy settings (dnd_enabled, who_can_call), start_direct_call enforcement,
-- and blocked users RPC.

-- 1. Ensure user_settings columns and constraints
alter table public.user_settings
  add column if not exists dnd_enabled boolean not null default false,
  add column if not exists who_can_call text not null default 'everyone';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'user_settings_who_can_call_check'
  ) then
    alter table public.user_settings
      add constraint user_settings_who_can_call_check
      check (who_can_call in ('everyone', 'saved_contacts', 'nobody'));
  end if;
end $$;

-- Synchronize existing settings rows safely
update public.user_settings
set dnd_enabled = coalesce(dnd_enabled, do_not_disturb, false),
    who_can_call = coalesce(
      case when who_can_call in ('everyone', 'saved_contacts', 'nobody') then who_can_call else null end,
      case when allow_calls = 'contacts' then 'saved_contacts' else allow_calls end,
      'everyone'
    );

-- 2. Update user default settings trigger
create or replace function public.ensure_voryn_user_defaults()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.user_settings (user_uid, dnd_enabled, who_can_call, show_online_status)
  values (new.id, false, 'everyone', true)
  on conflict (user_uid) do update
  set updated_at = now();
  return new;
end;
$$;

-- 3. Read own settings RPC
create or replace function public.get_my_settings()
returns table (
  user_uid uuid,
  dnd_enabled boolean,
  who_can_call text,
  show_online_status boolean
)
language sql stable security definer set search_path = '' as $$
  select s.user_uid,
         coalesce(s.dnd_enabled, s.do_not_disturb, false),
         coalesce(s.who_can_call, case when s.allow_calls = 'contacts' then 'saved_contacts' else s.allow_calls end, 'everyone'),
         coalesce(s.show_online_status, true)
  from public.user_settings s
  where s.user_uid = auth.uid();
$$;

revoke all on function public.get_my_settings() from public;
grant execute on function public.get_my_settings() to authenticated;

-- 4. Update own privacy settings RPC
create or replace function public.update_my_privacy_settings(
  new_dnd boolean default null,
  new_who_can_call text default null,
  new_show_online boolean default null
)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_who_can_call text := new_who_can_call;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if v_who_can_call is not null and v_who_can_call not in ('everyone', 'saved_contacts', 'nobody') then
    raise exception 'Invalid who_can_call value';
  end if;

  update public.user_settings
  set dnd_enabled = coalesce(new_dnd, dnd_enabled),
      do_not_disturb = coalesce(new_dnd, do_not_disturb),
      who_can_call = coalesce(v_who_can_call, who_can_call),
      allow_calls = case when v_who_can_call = 'saved_contacts' then 'contacts'
                         when v_who_can_call is not null then v_who_can_call
                         else allow_calls end,
      show_online_status = coalesce(new_show_online, show_online_status),
      updated_at = now()
  where user_uid = auth.uid();

  return found;
end;
$$;

revoke all on function public.update_my_privacy_settings(boolean, text, boolean) from public;
grant execute on function public.update_my_privacy_settings(boolean, text, boolean) to authenticated;

-- 5. List blocked users RPC
create or replace function public.list_blocked_users()
returns table (
  uid uuid,
  display_name text,
  voryn_id text,
  avatar_url text,
  blocked_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select p.uid,
         p.full_name as display_name,
         p.voryn_id,
         p.avatar_url,
         b.created_at as blocked_at
  from public.user_blocks b
  join public.profiles p on p.uid = b.blocked_uid
  where b.owner_uid = auth.uid()
  order by b.created_at desc;
$$;

revoke all on function public.list_blocked_users() from public;
grant execute on function public.list_blocked_users() to authenticated;

-- 6. start_direct_call with authoritative policy enforcement
create or replace function public.start_direct_call(candidate text, requested_type text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_uid uuid;
  new_call_id uuid;
  target_dnd boolean;
  target_who_can_call text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

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

  -- Enforce bidirectional blocks with privacy-preserving error
  if exists (
    select 1 from public.user_blocks b
    where (b.owner_uid = auth.uid() and b.blocked_uid = target_uid)
       or (b.owner_uid = target_uid and b.blocked_uid = auth.uid())
  ) then
    raise exception 'calling_unavailable';
  end if;

  -- Inspect target user's privacy and DND settings
  select coalesce(s.dnd_enabled, s.do_not_disturb, false),
         coalesce(s.who_can_call, case when s.allow_calls = 'contacts' then 'saved_contacts' else s.allow_calls end, 'everyone')
  into target_dnd, target_who_can_call
  from public.user_settings s
  where s.user_uid = target_uid;

  -- 1. Target DND check
  if target_dnd is true then
    raise exception 'dnd_enabled';
  end if;

  -- 2. Target Who Can Call Me check
  if target_who_can_call = 'nobody' then
    raise exception 'calls_disabled';
  elsif target_who_can_call = 'saved_contacts' then
    -- Verify target has saved the caller in target's user_contacts
    if not exists (
      select 1 from public.user_contacts uc
      where uc.owner_uid = target_uid and uc.contact_uid = auth.uid()
    ) then
      raise exception 'contacts_only';
    end if;
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

-- 7. Update set_voryn_user_blocked to support both Voryn ID and user UUID
create or replace function public.set_voryn_user_blocked(candidate text, is_blocked boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare target_uid uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select uid into target_uid from public.profiles
  where lower(voryn_id) = lower(trim(leading '@' from candidate))
     or uid::text = candidate;
  if target_uid is null or target_uid = auth.uid() then return false; end if;
  if is_blocked then
    insert into public.user_blocks (owner_uid, blocked_uid)
    values (auth.uid(), target_uid) on conflict do nothing;
  else
    delete from public.user_blocks
    where owner_uid = auth.uid() and blocked_uid = target_uid;
  end if;
  return true;
end;
$$;

revoke all on function public.set_voryn_user_blocked(text, boolean) from public;
grant execute on function public.set_voryn_user_blocked(text, boolean) to authenticated;

-- 8. Update submit_user_report to support both Voryn ID and user UUID with validated reasons
create or replace function public.submit_user_report(
  candidate text,
  report_reason text,
  report_details text default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  target_uid uuid;
  report_id uuid;
  v_reason text := lower(trim(report_reason));
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if v_reason not in ('spam', 'harassment', 'impersonation', 'suspicious_activity', 'other') then
    raise exception 'Invalid report reason';
  end if;

  select uid into target_uid from public.profiles
  where lower(voryn_id) = lower(trim(leading '@' from candidate))
     or uid::text = candidate;
  if target_uid is null or target_uid = auth.uid() then
    raise exception 'User not found';
  end if;

  insert into public.user_reports (reporter_uid, reported_uid, reason, details)
  values (auth.uid(), target_uid, v_reason, nullif(trim(report_details), ''))
  returning id into report_id;
  return report_id;
end;
$$;

revoke all on function public.submit_user_report(text, text, text) from public;
grant execute on function public.submit_user_report(text, text, text) to authenticated;

