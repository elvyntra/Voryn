-- Migration: 202609210001_persistent_call_messages.sql
-- Persistent Call Messages: canonical threads, push outbox, unread tracking, tuple pagination

-- 1. Create message_threads
create table if not exists public.message_threads (
  id uuid primary key default gen_random_uuid(),
  user_low uuid not null references auth.users(id) on delete cascade,
  user_high uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (user_low < user_high),
  unique (user_low, user_high)
);

-- 2. Create message_thread_members
create table if not exists public.message_thread_members (
  thread_id uuid not null references public.message_threads(id) on delete cascade,
  user_uid uuid not null references auth.users(id) on delete cascade,
  last_read_message_id uuid,
  last_read_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  primary key (thread_id, user_uid)
);

-- 3. Alter call_messages
alter table public.call_messages
  add column if not exists thread_id uuid references public.message_threads(id) on delete cascade,
  add column if not exists client_message_id text;

-- Backfill legacy rows into message_threads and message_thread_members
do $$
declare
  r record;
  t_id uuid;
  u_low uuid;
  u_high uuid;
begin
  for r in select distinct sender_uid, recipient_uid from public.call_messages where thread_id is null loop
    u_low := least(r.sender_uid, r.recipient_uid);
    u_high := greatest(r.sender_uid, r.recipient_uid);
    
    insert into public.message_threads (user_low, user_high)
    values (u_low, u_high)
    on conflict (user_low, user_high) do update set updated_at = now()
    returning id into t_id;
    
    insert into public.message_thread_members (thread_id, user_uid)
    values (t_id, u_low), (t_id, u_high)
    on conflict (thread_id, user_uid) do nothing;
    
    update public.call_messages
    set thread_id = t_id
    where thread_id is null
      and ((sender_uid = r.sender_uid and recipient_uid = r.recipient_uid)
        or (sender_uid = r.recipient_uid and recipient_uid = r.sender_uid));
  end loop;
end;
$$;

-- Make thread_id NOT NULL after backfill
alter table public.call_messages alter column thread_id set not null;

-- Indexes
create unique index if not exists call_messages_sender_client_id_idx
  on public.call_messages(sender_uid, client_message_id)
  where client_message_id is not null;

create index if not exists call_messages_thread_pagination_idx
  on public.call_messages (thread_id, created_at desc, id desc);

create index if not exists message_threads_users_idx
  on public.message_threads (user_low, user_high);

create index if not exists message_thread_members_user_idx
  on public.message_thread_members (user_uid, last_read_at desc);

-- 4. Create message_push_outbox
create table if not exists public.message_push_outbox (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.call_messages(id) on delete cascade,
  recipient_uid uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'delivered', 'failed')),
  retry_count int not null default 0,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists message_push_outbox_pending_idx
  on public.message_push_outbox (created_at asc)
  where status = 'pending';

-- 5. RLS Policies
alter table public.message_threads enable row level security;
alter table public.message_thread_members enable row level security;
alter table public.message_push_outbox enable row level security;

drop policy if exists "message_threads_member_read" on public.message_threads;
create policy "message_threads_member_read" on public.message_threads
  for select to authenticated
  using ((select auth.uid()) in (user_low, user_high));

drop policy if exists "message_thread_members_own_rows" on public.message_thread_members;
create policy "message_thread_members_own_rows" on public.message_thread_members
  for select to authenticated
  using ((select auth.uid()) = user_uid);

-- RLS for call_messages: select allowed for participants, insert solely via security definer RPC
drop policy if exists "call_messages_participant_rows" on public.call_messages;
drop policy if exists "call_messages_participant_select" on public.call_messages;
create policy "call_messages_participant_select" on public.call_messages
  for select to authenticated
  using ((select auth.uid()) in (sender_uid, recipient_uid));

revoke insert, update, delete on public.call_messages from authenticated;
grant select on public.call_messages to authenticated;
grant select on public.message_threads to authenticated;
grant select on public.message_thread_members to authenticated;

-- 6. RPC: get_or_create_direct_thread
create or replace function public.get_or_create_direct_thread(target_user_id uuid)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_caller_id uuid;
  v_low uuid;
  v_high uuid;
  v_thread_id uuid;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    raise exception 'Authentication required';
  end if;
  if target_user_id is null or target_user_id = v_caller_id then
    raise exception 'Invalid target user';
  end if;

  v_low := least(v_caller_id, target_user_id);
  v_high := greatest(v_caller_id, target_user_id);

  insert into public.message_threads (user_low, user_high, updated_at)
  values (v_low, v_high, now())
  on conflict (user_low, user_high)
  do update set updated_at = message_threads.updated_at
  returning id into v_thread_id;

  insert into public.message_thread_members (thread_id, user_uid)
  values (v_thread_id, v_low), (v_thread_id, v_high)
  on conflict (thread_id, user_uid) do nothing;

  return v_thread_id;
end;
$$;

-- 7. RPC: send_call_message
create or replace function public.send_call_message(
  candidate text default null,
  message_body text default null,
  remind boolean default false,
  p_recipient_uid uuid default null,
  p_body text default null,
  p_remind_to_call boolean default false,
  p_client_message_id text default null
)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_sender_uid uuid;
  v_target_uid uuid;
  v_text text;
  v_remind boolean;
  v_client_id text;
  v_thread_id uuid;
  v_message_id uuid;
  v_existing_id uuid;
begin
  v_sender_uid := auth.uid();
  if v_sender_uid is null then
    raise exception 'Authentication required';
  end if;

  -- Resolve recipient
  if p_recipient_uid is not null then
    v_target_uid := p_recipient_uid;
  elsif candidate is not null and trim(candidate) <> '' then
    select uid into v_target_uid from public.profiles
    where lower(voryn_id) = lower(trim(leading '@' from candidate));
  end if;

  if v_target_uid is null or v_target_uid = v_sender_uid then
    raise exception 'User not found';
  end if;

  -- Resolve text
  v_text := trim(coalesce(p_body, message_body, ''));
  if char_length(v_text) not between 1 and 120 then
    raise exception 'Invalid message length (1-120 characters)';
  end if;

  -- Resolve remind flag
  v_remind := coalesce(p_remind_to_call, remind, false);

  -- Resolve client_message_id
  v_client_id := nullif(trim(coalesce(p_client_message_id, '')), '');

  -- Idempotency check
  if v_client_id is not null then
    select id into v_existing_id
    from public.call_messages
    where sender_uid = v_sender_uid and client_message_id = v_client_id;

    if v_existing_id is not null then
      return v_existing_id;
    end if;
  end if;

  -- Check blocking
  if exists (
    select 1 from public.user_blocks b
    where (b.owner_uid = v_sender_uid and b.blocked_uid = v_target_uid)
       or (b.owner_uid = v_target_uid and b.blocked_uid = v_sender_uid)
  ) then
    raise exception 'Messaging unavailable';
  end if;

  -- Get or create direct thread
  v_thread_id := public.get_or_create_direct_thread(v_target_uid);

  -- Insert message
  insert into public.call_messages (
    thread_id,
    sender_uid,
    recipient_uid,
    body,
    remind_to_call,
    client_message_id,
    created_at
  )
  values (
    v_thread_id,
    v_sender_uid,
    v_target_uid,
    v_text,
    v_remind,
    v_client_id,
    now()
  )
  returning id into v_message_id;

  -- Update thread updated_at
  update public.message_threads
  set updated_at = now()
  where id = v_thread_id;

  -- Update sender's read cursor (sender has seen their own message)
  update public.message_thread_members
  set last_read_message_id = v_message_id,
      last_read_at = now()
  where thread_id = v_thread_id and user_uid = v_sender_uid;

  -- Enqueue push outbox
  insert into public.message_push_outbox (message_id, recipient_uid, status)
  values (v_message_id, v_target_uid, 'pending');

  return v_message_id;
end;
$$;

-- 8. RPC: list_my_message_threads
create or replace function public.list_my_message_threads()
returns table (
  thread_id uuid,
  other_user_uid uuid,
  other_user_name text,
  other_user_voryn_id text,
  other_user_avatar_url text,
  last_message_id uuid,
  last_message_body text,
  last_message_sender_uid uuid,
  last_message_created_at timestamptz,
  last_message_remind_to_call boolean,
  unread_count bigint
)
language sql stable security definer set search_path = '' as $$
  select
    t.id as thread_id,
    case when t.user_low = auth.uid() then t.user_high else t.user_low end as other_user_uid,
    coalesce(nullif(trim(other_p.full_name), ''), nullif(trim(other_p.voryn_id), ''), 'Voryn User') as other_user_name,
    other_p.voryn_id as other_user_voryn_id,
    other_p.avatar_url as other_user_avatar_url,
    last_msg.id as last_message_id,
    last_msg.body as last_message_body,
    last_msg.sender_uid as last_message_sender_uid,
    last_msg.created_at as last_message_created_at,
    last_msg.remind_to_call as last_message_remind_to_call,
    coalesce(unread.cnt, 0) as unread_count
  from public.message_threads t
  join public.message_thread_members my_m
    on my_m.thread_id = t.id and my_m.user_uid = auth.uid()
  left join public.profiles other_p
    on other_p.uid = case when t.user_low = auth.uid() then t.user_high else t.user_low end
  left join lateral (
    select cm.id, cm.body, cm.sender_uid, cm.created_at, cm.remind_to_call
    from public.call_messages cm
    where cm.thread_id = t.id
    order by cm.created_at desc, cm.id desc
    limit 1
  ) last_msg on true
  left join lateral (
    select count(*) as cnt
    from public.call_messages cm_u
    where cm_u.thread_id = t.id
      and cm_u.created_at > my_m.last_read_at
      and cm_u.sender_uid <> auth.uid()
  ) unread on true
  order by coalesce(last_msg.created_at, t.updated_at) desc;
$$;

-- 9. RPC: get_thread_messages (tuple-based pagination)
create or replace function public.get_thread_messages(
  p_thread_id uuid,
  p_limit int default 50,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null
)
returns table (
  id uuid,
  thread_id uuid,
  sender_uid uuid,
  recipient_uid uuid,
  sender_name text,
  sender_voryn_id text,
  body text,
  remind_to_call boolean,
  created_at timestamptz,
  client_message_id text
)
language sql stable security definer set search_path = '' as $$
  select
    cm.id,
    cm.thread_id,
    cm.sender_uid,
    cm.recipient_uid,
    coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.voryn_id), ''), 'Voryn User') as sender_name,
    p.voryn_id as sender_voryn_id,
    cm.body,
    cm.remind_to_call,
    cm.created_at,
    cm.client_message_id
  from public.call_messages cm
  join public.message_thread_members mtm
    on mtm.thread_id = cm.thread_id and mtm.user_uid = auth.uid()
  left join public.profiles p
    on p.uid = cm.sender_uid
  where cm.thread_id = p_thread_id
    and (
      p_before_created_at is null
      or (cm.created_at, cm.id) < (p_before_created_at, p_before_id)
    )
  order by cm.created_at desc, cm.id desc
  limit least(coalesce(p_limit, 50), 100);
$$;

-- 10. RPC: mark_thread_read
create or replace function public.mark_thread_read(
  p_thread_id uuid,
  p_last_seen_message_id uuid default null
)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_user_uid uuid;
  v_msg_created_at timestamptz;
begin
  v_user_uid := auth.uid();
  if v_user_uid is null then
    raise exception 'Authentication required';
  end if;

  if p_last_seen_message_id is not null then
    select created_at into v_msg_created_at
    from public.call_messages
    where id = p_last_seen_message_id and thread_id = p_thread_id;
  end if;

  update public.message_thread_members
  set last_read_message_id = coalesce(p_last_seen_message_id, last_read_message_id),
      last_read_at = greatest(last_read_at, coalesce(v_msg_created_at, now()))
  where thread_id = p_thread_id and user_uid = v_user_uid;

  return found;
end;
$$;

-- 11. Maintain legacy list_my_call_messages for backward compatibility
create or replace function public.list_my_call_messages()
returns table (
  id uuid, sender_uid uuid, sender_name text, sender_voryn_id text,
  body text, remind_to_call boolean, read_at timestamptz, created_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select cm.id, cm.sender_uid,
         coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.voryn_id), ''), 'Voryn User'),
         p.voryn_id,
         cm.body, cm.remind_to_call, cm.read_at, cm.created_at
  from public.call_messages cm
  left join public.profiles p on p.uid = cm.sender_uid
  where cm.recipient_uid = auth.uid()
  order by cm.created_at desc
  limit 200;
$$;

-- 12. Maintain legacy mark_call_message_read
create or replace function public.mark_call_message_read(message_uuid uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_thread_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  
  update public.call_messages set read_at = coalesce(read_at, now())
  where id = message_uuid and recipient_uid = auth.uid()
  returning thread_id into v_thread_id;

  if v_thread_id is not null then
    perform public.mark_thread_read(v_thread_id, message_uuid);
  end if;

  return found;
end;
$$;

-- 13. Grants
grant execute on function public.get_or_create_direct_thread(uuid) to authenticated;
grant execute on function public.send_call_message(text, text, boolean, uuid, text, boolean, text) to authenticated;
grant execute on function public.list_my_message_threads() to authenticated;
grant execute on function public.get_thread_messages(uuid, int, timestamptz, uuid) to authenticated;
grant execute on function public.mark_thread_read(uuid, uuid) to authenticated;
grant execute on function public.list_my_call_messages() to authenticated;
grant execute on function public.mark_call_message_read(uuid) to authenticated;

-- 14. Realtime publication
alter publication supabase_realtime add table public.call_messages;
alter table public.call_messages replica identity full;
