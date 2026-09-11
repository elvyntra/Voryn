create table if not exists public.profiles (
  uid uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text not null default '',
  voryn_id text,
  phone text,
  phone_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists full_name text not null default '';
alter table public.profiles add column if not exists voryn_id text;
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists phone_verified boolean not null default false;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

create unique index if not exists profiles_voryn_id_unique
  on public.profiles (lower(voryn_id))
  where voryn_id is not null;

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = uid);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check ((select auth.uid()) = uid);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using ((select auth.uid()) = uid)
  with check ((select auth.uid()) = uid);

create or replace function public.handle_new_voryn_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (uid, email, full_name, phone)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''),
    new.phone
  )
  on conflict (uid) do update
  set email = excluded.email,
      full_name = case
        when public.profiles.full_name = '' then excluded.full_name
        else public.profiles.full_name
      end,
      updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_voryn_profile on auth.users;
create trigger on_auth_user_created_voryn_profile
  after insert on auth.users
  for each row execute procedure public.handle_new_voryn_user();

insert into public.profiles (uid, email, full_name, phone)
select
  id,
  email,
  coalesce(raw_user_meta_data ->> 'full_name', raw_user_meta_data ->> 'name', ''),
  phone
from auth.users
on conflict (uid) do nothing;

create or replace function public.is_voryn_id_available(candidate text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    lower(trim(leading '@' from candidate)) ~ '^[a-z0-9_]{3,24}$'
    and lower(trim(leading '@' from candidate)) not in ('rahul', 'admin', 'support', 'voryn', 'test')
    and not exists (
      select 1
      from public.profiles
      where lower(voryn_id) = lower(trim(leading '@' from candidate))
        and uid <> auth.uid()
    );
$$;

create or replace function public.claim_voryn_id(candidate text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized text := lower(trim(leading '@' from candidate));
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if normalized !~ '^[a-z0-9_]{3,24}$' then
    raise exception 'Invalid Voryn ID';
  end if;
  if normalized in ('rahul', 'admin', 'support', 'voryn', 'test') then
    return false;
  end if;

  insert into public.profiles (uid, email, full_name, voryn_id, updated_at)
  select
    id,
    email,
    coalesce(raw_user_meta_data ->> 'full_name', raw_user_meta_data ->> 'name', ''),
    normalized,
    now()
  from auth.users
  where id = auth.uid()
  on conflict (uid) do update
  set voryn_id = excluded.voryn_id,
      updated_at = now();
  return true;
exception
  when unique_violation then
    return false;
end;
$$;

create or replace function public.find_user_by_voryn_id(candidate text)
returns table (
  uid uuid,
  display_name text,
  voryn_id text,
  phone text,
  presence text
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.uid, p.full_name, p.voryn_id, null::text, 'offline'::text
  from public.profiles p
  where lower(p.voryn_id) = lower(trim(leading '@' from candidate))
  limit 1;
$$;

revoke all on function public.is_voryn_id_available(text) from public;
revoke all on function public.claim_voryn_id(text) from public;
revoke all on function public.find_user_by_voryn_id(text) from public;
grant execute on function public.is_voryn_id_available(text) to authenticated;
grant execute on function public.claim_voryn_id(text) to authenticated;
grant execute on function public.find_user_by_voryn_id(text) to authenticated;
