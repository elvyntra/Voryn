-- Migration: 202609220001_message_edit_delete.sql
-- Message Edit and Delete with discrete Outbox Event IDs and Monotonic Versioning

-- 1. Schema adjustments for message_push_outbox
alter table public.message_push_outbox
  add column if not exists event_type text not null default 'created',
  add column if not exists message_version bigint not null default 1;

alter table public.message_push_outbox
  drop constraint if exists message_push_outbox_event_type_check;

alter table public.message_push_outbox
  add constraint message_push_outbox_event_type_check
  check (event_type in ('created', 'edited', 'deleted'));

-- Ensure no legacy UNIQUE(message_id) constraint or index exists on message_push_outbox
alter table public.message_push_outbox drop constraint if exists message_push_outbox_message_id_key;
drop index if exists public.message_push_outbox_message_id_key;
drop index if exists public.message_push_outbox_message_id_idx;
create index if not exists message_push_outbox_message_id_idx on public.message_push_outbox(message_id);

-- 2. Schema adjustments for call_messages
alter table public.call_messages
  alter column body drop not null;

alter table public.call_messages
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists message_version bigint not null default 1;

-- Drop legacy body length check constraint and add strict tombstone check constraint
alter table public.call_messages drop constraint if exists call_messages_body_check;
alter table public.call_messages drop constraint if exists call_messages_body_purge_check;

alter table public.call_messages add constraint call_messages_body_purge_check
  check (
    (deleted_at is null and body is not null and char_length(trim(body)) between 1 and 120)
    or
    (deleted_at is not null and body is null)
  );

-- 3. Replace Outbox Processor Functions (Event ID Based)
drop function if exists public.claim_message_push(uuid);
drop function if exists public.claim_message_push_event(uuid);

create or replace function public.claim_message_push_event(p_outbox_id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_updated int;
begin
  update public.message_push_outbox
  set status = 'processing',
      attempt_count = attempt_count + 1,
      processing_started_at = now()
  where id = p_outbox_id
    and status in ('pending', 'retry')
    and (
      status = 'pending'
      or next_attempt_at is null
      or next_attempt_at <= now()
    );
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

drop function if exists public.update_message_push_result(uuid, text, text);

create or replace function public.update_message_push_result(
  p_outbox_id uuid,
  p_status text,
  p_error text default null
)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_attempts int;
  v_delay interval;
begin
  select attempt_count into v_attempts
  from public.message_push_outbox
  where id = p_outbox_id;

  if p_status = 'sent' then
    update public.message_push_outbox
    set status = 'sent',
        processed_at = now(),
        last_error = p_error
    where id = p_outbox_id;
  elsif p_status = 'retry' then
    if coalesce(v_attempts, 0) >= 5 then
      update public.message_push_outbox
      set status = 'failed_terminal',
          processed_at = now(),
          last_error = coalesce(p_error, 'Max attempts exceeded (5)')
      where id = p_outbox_id;
    else
      -- Exponential backoff: 30s, 60s, 120s, 240s, 480s
      v_delay := make_interval(secs => (30 * (2 ^ coalesce(v_attempts, 0))));
      update public.message_push_outbox
      set status = 'retry',
          next_attempt_at = now() + v_delay,
          last_error = p_error
      where id = p_outbox_id;
    end if;
  else
    update public.message_push_outbox
    set status = p_status,
        processed_at = now(),
        last_error = p_error
    where id = p_outbox_id;
  end if;
end;
$$;

drop function if exists public.dispatch_message_push(uuid);

create or replace function public.dispatch_message_push(p_outbox_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_function_url text;
  v_internal_secret text;
begin
  select decrypted_secret into v_function_url
  from vault.decrypted_secrets
  where name = 'push_function_url'
  limit 1;

  if v_function_url is null or trim(v_function_url) = '' then
    v_function_url := 'https://nrkaqtrsrfozqyzqbwth.supabase.co/functions/v1/send-message-notification';
  end if;

  select decrypted_secret into v_internal_secret
  from vault.decrypted_secrets
  where name = 'internal_push_secret'
  limit 1;

  if v_internal_secret is null then
    v_internal_secret := current_setting('app.settings.internal_push_secret', true);
  end if;

  begin
    perform net.http_post(
      url := v_function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-internal-secret', coalesce(v_internal_secret, '')
      ),
      body := jsonb_build_object(
        'outboxId', p_outbox_id
      ),
      timeout_milliseconds := 10000
    );
  exception when others then
    null;
  end;
end;
$$;

create or replace function public.tr_process_message_push_outbox()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.dispatch_message_push(new.id);
  return new;
end;
$$;

drop trigger if exists tr_message_push_outbox_insert on public.message_push_outbox;
create trigger tr_message_push_outbox_insert
  after insert on public.message_push_outbox
  for each row
  execute function public.tr_process_message_push_outbox();

create or replace function public.process_due_message_pushes()
returns int
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v_count int := 0;
begin
  perform public.recover_stale_message_pushes();

  for r in
    select id
    from public.message_push_outbox
    where status in ('pending', 'retry')
      and next_attempt_at <= now()
    order by created_at asc
    limit 10
  loop
    perform public.dispatch_message_push(r.id);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- 4. Update send_call_message with explicit event_type and version
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

  -- Insert message with message_version = 1
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
    now(),
    now()
  )
  returning id into v_message_id;

  -- Update thread updated_at
  update public.message_threads
  set updated_at = now()
  where id = v_thread_id;

  -- Update sender's read cursor
  update public.message_thread_members
  set last_read_message_id = v_message_id,
      last_read_at = now()
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

-- 5. RPC: edit_call_message
drop function if exists public.edit_call_message(uuid, text);

create or replace function public.edit_call_message(
  p_message_id uuid,
  p_body text
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
language plpgsql security definer set search_path = '' as $$
declare
  v_caller_id uuid;
  v_sender_uid uuid;
  v_recipient_uid uuid;
  v_deleted_at timestamptz;
  v_current_version bigint;
  v_new_version bigint;
  v_text text;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    raise exception 'Authentication required';
  end if;

  v_text := trim(coalesce(p_body, ''));
  if char_length(v_text) not between 1 and 120 then
    raise exception 'Invalid message length (1-120 characters)';
  end if;

  select cm.sender_uid, cm.recipient_uid, cm.deleted_at, cm.message_version
  into v_sender_uid, v_recipient_uid, v_deleted_at, v_current_version
  from public.call_messages cm
  where cm.id = p_message_id;

  if not found then
    raise exception 'Message not found';
  end if;

  if v_sender_uid <> v_caller_id then
    raise exception 'Permission denied: only sender can edit';
  end if;

  if v_deleted_at is not null then
    raise exception 'Cannot edit deleted message';
  end if;

  v_new_version := coalesce(v_current_version, 1) + 1;

  -- Update message row (thread_id and message_threads.updated_at remain untouched)
  update public.call_messages
  set body = v_text,
      edited_at = now(),
      updated_at = now(),
      message_version = v_new_version
  where call_messages.id = p_message_id;

  -- Enqueue push outbox row for edit mutation
  insert into public.message_push_outbox (
    message_id,
    recipient_uid,
    event_type,
    message_version,
    status
  ) values (
    p_message_id,
    v_recipient_uid,
    'edited',
    v_new_version,
    'pending'
  );

  return query
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
    cm.client_message_id,
    cm.edited_at,
    cm.deleted_at,
    cm.message_version
  from public.call_messages cm
  left join public.profiles p on p.uid = cm.sender_uid
  where cm.id = p_message_id;
end;
$$;

-- 6. RPC: delete_call_message
drop function if exists public.delete_call_message(uuid);

create or replace function public.delete_call_message(p_message_id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_caller_id uuid;
  v_sender_uid uuid;
  v_recipient_uid uuid;
  v_deleted_at timestamptz;
  v_current_version bigint;
  v_new_version bigint;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    raise exception 'Authentication required';
  end if;

  select sender_uid, recipient_uid, deleted_at, message_version
  into v_sender_uid, v_recipient_uid, v_deleted_at, v_current_version
  from public.call_messages
  where call_messages.id = p_message_id;

  if not found then
    raise exception 'Message not found';
  end if;

  if v_sender_uid <> v_caller_id then
    raise exception 'Permission denied: only sender can delete';
  end if;

  -- Idempotency: if already deleted, return success immediately
  if v_deleted_at is not null then
    return true;
  end if;

  v_new_version := coalesce(v_current_version, 1) + 1;

  -- Soft delete: set body to NULL, deleted_at to now()
  update public.call_messages
  set body = null,
      deleted_at = now(),
      updated_at = now(),
      message_version = v_new_version
  where call_messages.id = p_message_id;

  -- Enqueue push outbox row for delete mutation
  insert into public.message_push_outbox (
    message_id,
    recipient_uid,
    event_type,
    message_version,
    status
  ) values (
    p_message_id,
    v_recipient_uid,
    'deleted',
    v_new_version,
    'pending'
  );

  return true;
end;
$$;

-- 7. Update list_my_message_threads
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
    case when last_msg.deleted_at is not null then 'Message deleted' else last_msg.body end as last_message_body,
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
    select cm.id, cm.body, cm.sender_uid, cm.created_at, cm.remind_to_call, cm.deleted_at
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
      and cm_u.deleted_at is null
  ) unread on true
  order by coalesce(last_msg.created_at, t.updated_at) desc;
$$;

-- 8. Update get_thread_messages
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

-- 9. Security Grants and Permissions
revoke insert, update, delete on public.call_messages from authenticated;
grant select on public.call_messages to authenticated;

grant execute on function public.send_call_message(text, text, boolean, uuid, text, boolean, text) to authenticated;
grant execute on function public.edit_call_message(uuid, text) to authenticated;
grant execute on function public.delete_call_message(uuid) to authenticated;
grant execute on function public.list_my_message_threads() to authenticated;
grant execute on function public.get_thread_messages(uuid, int, timestamptz, uuid) to authenticated;

grant execute on function public.claim_message_push_event(uuid) to service_role, postgres;
grant execute on function public.update_message_push_result(uuid, text, text) to service_role, postgres;
grant execute on function public.dispatch_message_push(uuid) to service_role, postgres;
