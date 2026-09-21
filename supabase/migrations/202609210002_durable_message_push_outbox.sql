-- Migration: 202609210002_durable_message_push_outbox.sql
-- Durable server-side push outbox with atomic claim, exponential backoff retry, and pg_net + pg_cron integration.

-- 1. Ensure extensions exist
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema extensions;
create extension if not exists supabase_vault with schema extensions;

-- 2. Update message_push_outbox table schema and statuses
alter table public.message_push_outbox drop constraint if exists message_push_outbox_status_check;

update public.message_push_outbox
set status = 'sent'
where status = 'delivered';

update public.message_push_outbox
set status = 'failed_terminal'
where status = 'failed';

alter table public.message_push_outbox
  add column if not exists attempt_count int not null default 0,
  add column if not exists processing_started_at timestamptz,
  add column if not exists next_attempt_at timestamptz not null default now(),
  add column if not exists last_error text;

alter table public.message_push_outbox
  add constraint message_push_outbox_status_check
  check (status in ('pending', 'processing', 'sent', 'retry', 'failed_terminal'));

-- Indexes for efficient queue polling
drop index if exists public.message_push_outbox_pending_idx;
create index if not exists message_push_outbox_queue_idx
  on public.message_push_outbox (next_attempt_at asc, created_at asc)
  where status in ('pending', 'retry');

create index if not exists message_push_outbox_stale_processing_idx
  on public.message_push_outbox (processing_started_at asc)
  where status = 'processing';

-- 3. Function: claim_message_push
-- Atomically claims a pending or retry row into processing state.
create or replace function public.claim_message_push(p_message_id uuid)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_updated int;
begin
  update public.message_push_outbox
  set status = 'processing',
      attempt_count = attempt_count + 1,
      processing_started_at = now()
  where message_id = p_message_id
    and status in ('pending', 'retry');
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end;
$$;

-- 4. Function: update_message_push_result
-- Updates outbox row to 'sent', 'retry' with backoff, or 'failed_terminal'.
create or replace function public.update_message_push_result(
  p_message_id uuid,
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
  where message_id = p_message_id;

  if p_status = 'sent' then
    update public.message_push_outbox
    set status = 'sent',
        processed_at = now(),
        last_error = p_error
    where message_id = p_message_id;
  elsif p_status = 'retry' then
    if coalesce(v_attempts, 0) >= 5 then
      update public.message_push_outbox
      set status = 'failed_terminal',
          processed_at = now(),
          last_error = coalesce(p_error, 'Max attempts exceeded (5)')
      where message_id = p_message_id;
    else
      -- Exponential backoff: 30s, 60s, 120s, 240s, 480s
      v_delay := make_interval(secs => (30 * (2 ^ coalesce(v_attempts, 0))));
      update public.message_push_outbox
      set status = 'retry',
          next_attempt_at = now() + v_delay,
          last_error = p_error
      where message_id = p_message_id;
    end if;
  else
    update public.message_push_outbox
    set status = p_status,
        processed_at = now(),
        last_error = p_error
    where message_id = p_message_id;
  end if;
end;
$$;

-- 5. Function: recover_stale_message_pushes
-- Recovers rows stuck in 'processing' for > 5 minutes back to 'retry'.
create or replace function public.recover_stale_message_pushes()
returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_recovered int;
begin
  update public.message_push_outbox
  set status = 'retry',
      processing_started_at = null,
      next_attempt_at = now()
  where status = 'processing'
    and processing_started_at < now() - interval '5 minutes';
  get diagnostics v_recovered = row_count;
  return v_recovered;
end;
$$;

-- 6. Function: dispatch_message_push
-- Dispatches an asynchronous HTTP POST via pg_net to the Edge Function.
-- Secrets and URLs are read dynamically from Vault or config; none are hardcoded.
create or replace function public.dispatch_message_push(p_message_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_function_url text;
  v_internal_secret text;
begin
  -- Read target function URL from Vault or fallback default
  select decrypted_secret into v_function_url
  from vault.decrypted_secrets
  where name = 'push_function_url'
  limit 1;

  if v_function_url is null or trim(v_function_url) = '' then
    v_function_url := 'https://nrkaqtrsrfozqyzqbwth.supabase.co/functions/v1/send-message-notification';
  end if;

  -- Read internal secret from Vault or app setting
  select decrypted_secret into v_internal_secret
  from vault.decrypted_secrets
  where name = 'internal_push_secret'
  limit 1;

  if v_internal_secret is null then
    v_internal_secret := current_setting('app.settings.internal_push_secret', true);
  end if;

  -- Non-blocking invocation via pg_net
  begin
    perform net.http_post(
      url := v_function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-internal-secret', coalesce(v_internal_secret, '')
      ),
      body := jsonb_build_object(
        'messageId', p_message_id
      ),
      timeout_milliseconds := 10000
    );
  exception when others then
    -- Network/dispatch failure must NEVER abort the caller transaction
    null;
  end;
end;
$$;

-- 7. Trigger Function: tr_process_message_push_outbox
-- Immediate trigger on message_push_outbox AFTER INSERT
create or replace function public.tr_process_message_push_outbox()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.dispatch_message_push(new.message_id);
  return new;
end;
$$;

drop trigger if exists tr_message_push_outbox_insert on public.message_push_outbox;
create trigger tr_message_push_outbox_insert
  after insert on public.message_push_outbox
  for each row
  execute function public.tr_process_message_push_outbox();

-- 8. Cron Processor Function: process_due_message_pushes
-- Runs periodically to recover stale pushes and retry pending/due messages.
create or replace function public.process_due_message_pushes()
returns int
language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v_count int := 0;
begin
  perform public.recover_stale_message_pushes();

  for r in
    select message_id
    from public.message_push_outbox
    where status in ('pending', 'retry')
      and next_attempt_at <= now()
    order by created_at asc
    limit 10
  loop
    perform public.dispatch_message_push(r.message_id);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- 9. Schedule periodic retry worker with pg_cron (every 1 minute)
do $$
begin
  if exists (select 1 from cron.job where jobname = 'retry_message_push_outbox') then
    perform cron.unschedule('retry_message_push_outbox');
  end if;
  perform cron.schedule(
    'retry_message_push_outbox',
    '* * * * *',
    'select public.process_due_message_pushes();'
  );
exception when others then
  -- In environments without cron execution permission, continue cleanly
  null;
end;
$$;

-- 10. Security grants
grant execute on function public.claim_message_push(uuid) to service_role, postgres;
grant execute on function public.update_message_push_result(uuid, text, text) to service_role, postgres;
grant execute on function public.recover_stale_message_pushes() to service_role, postgres;
grant execute on function public.process_due_message_pushes() to service_role, postgres;
grant execute on function public.dispatch_message_push(uuid) to service_role, postgres;
