create table if not exists public.user_contacts (
  owner_uid uuid not null references auth.users(id) on delete cascade,
  contact_uid uuid not null references public.profiles(uid) on delete cascade,
  custom_name text,
  device_name text,
  known_phone text,
  device_contact_id text,
  source text not null default 'voryn' check (source in ('voryn', 'device', 'matched')),
  favorite boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (owner_uid, contact_uid),
  check (owner_uid <> contact_uid)
);

create table if not exists public.user_blocks (
  owner_uid uuid not null references auth.users(id) on delete cascade,
  blocked_uid uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_uid, blocked_uid),
  check (owner_uid <> blocked_uid)
);

alter table public.user_contacts enable row level security;
alter table public.user_blocks enable row level security;

drop policy if exists "contacts_own_rows" on public.user_contacts;
create policy "contacts_own_rows" on public.user_contacts
  for all to authenticated
  using ((select auth.uid()) = owner_uid)
  with check ((select auth.uid()) = owner_uid);

drop policy if exists "blocks_own_rows" on public.user_blocks;
create policy "blocks_own_rows" on public.user_blocks
  for all to authenticated
  using ((select auth.uid()) = owner_uid)
  with check ((select auth.uid()) = owner_uid);

create or replace function public.save_voryn_contact(
  candidate text,
  saved_name text,
  is_favorite boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare target_uid uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select uid into target_uid from public.profiles
  where lower(voryn_id) = lower(trim(leading '@' from candidate));
  if target_uid is null or target_uid = auth.uid() then return false; end if;
  insert into public.user_contacts (owner_uid, contact_uid, custom_name, source, favorite)
  values (auth.uid(), target_uid, nullif(trim(saved_name), ''), 'voryn', is_favorite)
  on conflict (owner_uid, contact_uid) do update
  set custom_name = excluded.custom_name,
      favorite = excluded.favorite,
      updated_at = now();
  return true;
end;
$$;

create or replace function public.set_voryn_contact_favorite(candidate text, is_favorite boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare target_uid uuid;
begin
  select uid into target_uid from public.profiles
  where lower(voryn_id) = lower(trim(leading '@' from candidate));
  update public.user_contacts set favorite = is_favorite, updated_at = now()
  where owner_uid = auth.uid() and contact_uid = target_uid;
  return found;
end;
$$;

create or replace function public.remove_voryn_contact(candidate text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare target_uid uuid;
begin
  select uid into target_uid from public.profiles
  where lower(voryn_id) = lower(trim(leading '@' from candidate));
  delete from public.user_contacts
  where owner_uid = auth.uid() and contact_uid = target_uid;
  return found;
end;
$$;

create or replace function public.set_voryn_user_blocked(candidate text, is_blocked boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare target_uid uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select uid into target_uid from public.profiles
  where lower(voryn_id) = lower(trim(leading '@' from candidate));
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

create or replace function public.list_my_contacts()
returns table (
  uid uuid, name text, voryn_id text, display_name text,
  phone text, favorite boolean, blocked boolean
)
language sql stable security definer set search_path = '' as $$
  select p.uid,
         p.full_name,
         p.voryn_id,
         coalesce(nullif(c.device_name, ''), nullif(c.custom_name, ''), nullif(p.full_name, ''), p.voryn_id),
         c.known_phone,
         c.favorite,
         exists(select 1 from public.user_blocks b
                where b.owner_uid = auth.uid() and b.blocked_uid = p.uid)
  from public.user_contacts c
  join public.profiles p on p.uid = c.contact_uid
  where c.owner_uid = auth.uid() and p.voryn_id is not null
  order by lower(coalesce(nullif(c.device_name, ''), nullif(c.custom_name, ''), p.full_name, p.voryn_id));
$$;

create or replace function public.sync_phone_contacts(
  phone_numbers text[], device_names text[], device_ids text[]
)
returns table (
  uid uuid, name text, voryn_id text, display_name text,
  phone text, favorite boolean, blocked boolean
)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if coalesce(array_length(phone_numbers, 1), 0) > 5000 then
    raise exception 'Too many contacts in one sync';
  end if;

  insert into public.user_contacts (
    owner_uid, contact_uid, device_name, known_phone, device_contact_id, source
  )
  select auth.uid(), p.uid, nullif(trim(i.device_name), ''), i.phone_number,
         nullif(i.device_id, ''), 'matched'
  from unnest(phone_numbers, device_names, device_ids)
       as i(phone_number, device_name, device_id)
  join public.profiles p
    on regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') = i.phone_number
   and p.voryn_id is not null
  where p.uid <> auth.uid()
  on conflict (owner_uid, contact_uid) do update
  set device_name = excluded.device_name,
      known_phone = excluded.known_phone,
      device_contact_id = excluded.device_contact_id,
      source = case when public.user_contacts.source = 'voryn'
                    then public.user_contacts.source else 'matched' end,
      updated_at = now();

  return query select * from public.list_my_contacts();
end;
$$;

revoke all on public.user_contacts from anon;
revoke all on public.user_blocks from anon;
grant select, insert, update, delete on public.user_contacts to authenticated;
grant select, insert, update, delete on public.user_blocks to authenticated;
revoke all on function public.save_voryn_contact(text, text, boolean) from public;
revoke all on function public.set_voryn_contact_favorite(text, boolean) from public;
revoke all on function public.remove_voryn_contact(text) from public;
revoke all on function public.set_voryn_user_blocked(text, boolean) from public;
revoke all on function public.list_my_contacts() from public;
revoke all on function public.sync_phone_contacts(text[], text[], text[]) from public;
grant execute on function public.save_voryn_contact(text, text, boolean) to authenticated;
grant execute on function public.set_voryn_contact_favorite(text, boolean) to authenticated;
grant execute on function public.remove_voryn_contact(text) to authenticated;
grant execute on function public.set_voryn_user_blocked(text, boolean) to authenticated;
grant execute on function public.list_my_contacts() to authenticated;
grant execute on function public.sync_phone_contacts(text[], text[], text[]) to authenticated;
