-- Migration: 202609220002_message_user_visibility.sql
-- Delete for Me & Clear Chat (Private Account-Level Visibility & Monotonic Clear Cursor)

-- 1. Create table public.message_user_hidden_messages
create table if not exists public.message_user_hidden_messages (
  user_uid uuid not null references auth.users(id) on delete cascade,
  message_id uuid not null references public.call_messages(id) on delete cascade,
  thread_id uuid not null references public.message_threads(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (user_uid, message_id)
);

create index if not exists message_user_hidden_messages_user_thread_idx
  on public.message_user_hidden_messages (user_uid, thread_id);

alter table public.message_user_hidden_messages enable row level security;

drop policy if exists "Users can select their own hidden messages" on public.message_user_hidden_messages;
create policy "Users can select their own hidden messages"
  on public.message_user_hidden_messages
  for select
  using (user_uid = auth.uid());

revoke insert, update, delete on public.message_user_hidden_messages from authenticated;
grant select on public.message_user_hidden_messages to authenticated;

-- 2. Create table public.message_user_thread_state
create table if not exists public.message_user_thread_state (
  user_uid uuid not null references auth.users(id) on delete cascade,
  thread_id uuid not null references public.message_threads(id) on delete cascade,
  cleared_before_created_at timestamptz,
  cleared_before_message_id uuid,
  cleared_at timestamptz not null default now(),
  primary key (user_uid, thread_id)
);

alter table public.message_user_thread_state enable row level security;

drop policy if exists "Users can select their own thread state" on public.message_user_thread_state;
create policy "Users can select their own thread state"
  on public.message_user_thread_state
  for select
  using (user_uid = auth.uid());

revoke insert, update, delete on public.message_user_thread_state from authenticated;
grant select on public.message_user_thread_state to authenticated;

-- 3. Idempotent Realtime Publication Membership
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'message_user_hidden_messages'
  ) then
    alter publication supabase_realtime add table public.message_user_hidden_messages;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'message_user_thread_state'
  ) then
    alter publication supabase_realtime add table public.message_user_thread_state;
  end if;
end;
$$;

-- 4. RPC: delete_call_message_for_me
drop function if exists public.delete_call_message_for_me(uuid);

create or replace function public.delete_call_message_for_me(p_message_id uuid)
returns table (
  out_message_id uuid,
  out_thread_id uuid,
  out_hidden_at timestamptz
)
language plpgsql security definer set search_path = '' as $$
declare
  v_caller_id uuid;
  v_thread_id uuid;
  v_hidden_at timestamptz;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    raise exception 'Authentication required';
  end if;

  -- Derive thread_id directly from canonical call_messages row
  select cm.thread_id into v_thread_id
  from public.call_messages cm
  where cm.id = p_message_id;

  if not found then
    raise exception 'Message not found';
  end if;

  -- Verify caller is a member of the thread
  if not exists (
    select 1 from public.message_thread_members mtm
    where mtm.thread_id = v_thread_id and mtm.user_uid = v_caller_id
  ) then
    raise exception 'Permission denied: caller is not a member of this thread';
  end if;

  -- Insert into private hidden messages (idempotent)
  insert into public.message_user_hidden_messages as muhm (
    user_uid,
    message_id,
    thread_id,
    hidden_at
  ) values (
    v_caller_id,
    p_message_id,
    v_thread_id,
    now()
  )
  on conflict (user_uid, message_id) do update
    set hidden_at = muhm.hidden_at
  returning muhm.hidden_at into v_hidden_at;

  return query
  select p_message_id, v_thread_id, v_hidden_at;
end;
$$;

-- 5. RPC: clear_call_message_thread
drop function if exists public.clear_call_message_thread(uuid);

create or replace function public.clear_call_message_thread(p_thread_id uuid)
returns table (
  out_thread_id uuid,
  out_cleared_before_created_at timestamptz,
  out_cleared_before_message_id uuid,
  out_cleared_at timestamptz
)
language plpgsql security definer set search_path = '' as $$
declare
  v_caller_id uuid;
  v_latest_id uuid;
  v_latest_created_at timestamptz;
  v_res_created_at timestamptz;
  v_res_id uuid;
  v_res_cleared_at timestamptz;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    raise exception 'Authentication required';
  end if;

  -- Verify caller is a member of the thread
  if not exists (
    select 1 from public.message_thread_members mtm
    where mtm.thread_id = p_thread_id and mtm.user_uid = v_caller_id
  ) then
    raise exception 'Permission denied: caller is not a member of this thread';
  end if;

  -- Select latest committed canonical message in thread
  select cm.id, cm.created_at
  into v_latest_id, v_latest_created_at
  from public.call_messages cm
  where cm.thread_id = p_thread_id
  order by cm.created_at desc, cm.id desc
  limit 1;

  -- Monotonic UPSERT: only move clear cursor forward
  insert into public.message_user_thread_state as muts (
    user_uid,
    thread_id,
    cleared_before_created_at,
    cleared_before_message_id,
    cleared_at
  ) values (
    v_caller_id,
    p_thread_id,
    v_latest_created_at,
    v_latest_id,
    clock_timestamp()
  )
  on conflict (user_uid, thread_id) do update
    set cleared_before_created_at = excluded.cleared_before_created_at,
        cleared_before_message_id = excluded.cleared_before_message_id,
        cleared_at = excluded.cleared_at
    where muts.cleared_before_created_at is null
       or (excluded.cleared_before_created_at, excluded.cleared_before_message_id) > (muts.cleared_before_created_at, muts.cleared_before_message_id)
  returning
    muts.cleared_before_created_at,
    muts.cleared_before_message_id,
    muts.cleared_at
  into
    v_res_created_at,
    v_res_id,
    v_res_cleared_at;

  -- If update condition was false (i.e. existing cursor was already newer), read current stored values
  if not found then
    select
      muts.cleared_before_created_at,
      muts.cleared_before_message_id,
      muts.cleared_at
    into
      v_res_created_at,
      v_res_id,
      v_res_cleared_at
    from public.message_user_thread_state muts
    where muts.user_uid = v_caller_id and muts.thread_id = p_thread_id;
  end if;

  return query
  select p_thread_id, v_res_created_at, v_res_id, v_res_cleared_at;
end;
$$;

-- 5b. Update send_call_message to use clock_timestamp() for monotonic created_at
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
  v_now timestamptz;
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

  v_remind := coalesce(p_remind_to_call, remind, false);
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
  v_now := clock_timestamp();

  -- Insert message with message_version = 1 and clock_timestamp
  insert into public.call_messages (
    thread_id,
    sender_uid,
    recipient_uid,
    body,
    remind_to_call,
    client_message_id,
    message_version,
    created_at,
    updated_at
  )
  values (
    v_thread_id,
    v_sender_uid,
    v_target_uid,
    v_text,
    v_remind,
    v_client_id,
    1,
    v_now,
    v_now
  )
  returning id into v_message_id;

  -- Update thread updated_at
  update public.message_threads
  set updated_at = v_now
  where id = v_thread_id;

  -- Update sender's read cursor
  update public.message_thread_members
  set last_read_message_id = v_message_id,
      last_read_at = v_now
  where thread_id = v_thread_id and user_uid = v_sender_uid;

  -- Enqueue push outbox with explicit event_type and version
  insert into public.message_push_outbox (
    message_id,
    recipient_uid,
    event_type,
    message_version,
    status
  )
  values (
    v_message_id,
    v_target_uid,
    'created',
    1,
    'pending'
  );

  return v_message_id;
end;
$$;

-- 6. Update get_thread_messages with private visibility filters applied before LIMIT
drop function if exists public.get_thread_messages(uuid, int, timestamptz, uuid);

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
  client_message_id text,
  edited_at timestamptz,
  deleted_at timestamptz,
  message_version bigint
)
language sql stable security definer set search_path = '' as $$
  select
    cm.id,
    cm.thread_id,
    cm.sender_uid,
    cm.recipient_uid,
    coalesce(nullif(trim(p.full_name), ''), nullif(trim(p.voryn_id), ''), 'Voryn User') as sender_name,
    p.voryn_id as sender_voryn_id,
    case when cm.deleted_at is not null then null else cm.body end as body,
    cm.remind_to_call,
    cm.created_at,
    cm.client_message_id,
    cm.edited_at,
    cm.deleted_at,
    cm.message_version
  from public.call_messages cm
  join public.message_thread_members mtm
    on mtm.thread_id = cm.thread_id and mtm.user_uid = auth.uid()
  left join public.message_user_thread_state muts
    on muts.thread_id = cm.thread_id and muts.user_uid = auth.uid()
  left join public.profiles p
    on p.uid = cm.sender_uid
  where cm.thread_id = p_thread_id
    -- Exclude individually hidden messages for auth.uid()
    and not exists (
      select 1 from public.message_user_hidden_messages muhm
      where muhm.user_uid = auth.uid() and muhm.message_id = cm.id
    )
    -- Exclude messages at or before the clear cursor
    and (
      muts.cleared_before_created_at is null
      or (cm.created_at, cm.id) > (muts.cleared_before_created_at, muts.cleared_before_message_id)
    )
    -- Keyset pagination
    and (
      p_before_created_at is null
      or (cm.created_at, cm.id) < (p_before_created_at, p_before_id)
    )
  order by cm.created_at desc, cm.id desc
  limit least(coalesce(p_limit, 50), 100);
$$;

-- 7. Update list_my_message_threads with private visibility filters and clean empty preview
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
    case
      when last_msg.id is null then null
      when last_msg.deleted_at is not null then 'Message deleted'
      else last_msg.body
    end as last_message_body,
    last_msg.sender_uid as last_message_sender_uid,
    last_msg.created_at as last_message_created_at,
    coalesce(last_msg.remind_to_call, false) as last_message_remind_to_call,
    coalesce(unread.cnt, 0) as unread_count
  from public.message_threads t
  join public.message_thread_members my_m
    on my_m.thread_id = t.id and my_m.user_uid = auth.uid()
  left join public.profiles other_p
    on other_p.uid = case when t.user_low = auth.uid() then t.user_high else t.user_low end
  left join public.message_user_thread_state muts
    on muts.thread_id = t.id and muts.user_uid = auth.uid()
  left join lateral (
    select cm.id, cm.body, cm.sender_uid, cm.created_at, cm.remind_to_call, cm.deleted_at
    from public.call_messages cm
    where cm.thread_id = t.id
      -- Exclude individually hidden messages for auth.uid()
      and not exists (
        select 1 from public.message_user_hidden_messages muhm
        where muhm.user_uid = auth.uid() and muhm.message_id = cm.id
      )
      -- Exclude messages at or before clear cursor
      and (
        muts.cleared_before_created_at is null
        or (cm.created_at, cm.id) > (muts.cleared_before_created_at, muts.cleared_before_message_id)
      )
    order by cm.created_at desc, cm.id desc
    limit 1
  ) last_msg on true
  left join lateral (
    select count(*) as cnt
    from public.call_messages cm_u
    where cm_u.thread_id = t.id
      and cm_u.created_at > my_m.last_read_at
      and cm_u.sender_uid <> auth.uid()
      and cm_u.deleted_at is null
      and not exists (
        select 1 from public.message_user_hidden_messages muhm
        where muhm.user_uid = auth.uid() and muhm.message_id = cm_u.id
      )
      and (
        muts.cleared_before_created_at is null
        or (cm_u.created_at, cm_u.id) > (muts.cleared_before_created_at, muts.cleared_before_message_id)
      )
  ) unread on true
  order by coalesce(last_msg.created_at, to_timestamp(0)) desc, t.updated_at desc;
$$;

-- 8. Security Grants
grant execute on function public.delete_call_message_for_me(uuid) to authenticated;
grant execute on function public.clear_call_message_thread(uuid) to authenticated;
grant execute on function public.get_thread_messages(uuid, int, timestamptz, uuid) to authenticated;
grant execute on function public.list_my_message_threads() to authenticated;
