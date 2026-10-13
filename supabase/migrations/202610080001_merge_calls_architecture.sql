-- Migration: 202610080001_merge_calls_architecture
-- Description: Two-Phase Call Merge Database Foundation (Prepare, Provisional Join, Trusted Commit, Cancel, RLS)
-- Checkpoint: MC-2A

-- 1. Add merged_into_call_id to public.calls
alter table public.calls
  add column if not exists merged_into_call_id uuid references public.calls(id) on delete set null;

create index if not exists idx_calls_merged_into_call_id
  on public.calls(merged_into_call_id)
  where merged_into_call_id is not null;

-- 2. Create public.call_merge_operations table
create table if not exists public.call_merge_operations (
  id uuid primary key default gen_random_uuid(),
  primary_call_id uuid not null references public.calls(id) on delete cascade,
  secondary_call_id uuid not null references public.calls(id) on delete cascade,
  initiated_by uuid not null references auth.users(id),
  joining_user_uid uuid not null references auth.users(id),
  status text not null check (status in ('prepared', 'joining', 'committed', 'cancelled', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 seconds'),
  committed_at timestamptz,
  cancelled_at timestamptz,
  constraint call_merge_distinct_calls check (primary_call_id <> secondary_call_id)
);

-- Indexes for fast query and lookup
create index if not exists idx_call_merge_operations_active
  on public.call_merge_operations(primary_call_id, joining_user_uid, status)
  where status in ('prepared', 'joining');

create index if not exists idx_call_merge_operations_secondary
  on public.call_merge_operations(secondary_call_id);

create index if not exists idx_call_merge_operations_initiated_by
  on public.call_merge_operations(initiated_by);

-- Enable Row-Level Security
alter table public.call_merge_operations enable row level security;

-- RLS Policy: Authenticated participants, initiator, and joining user can inspect merge operations
drop policy if exists "call_merge_operations_select" on public.call_merge_operations;
create policy "call_merge_operations_select" on public.call_merge_operations
  for select to authenticated
  using (
    initiated_by = (select auth.uid())
    or joining_user_uid = (select auth.uid())
    or public.is_call_participant(primary_call_id, (select auth.uid()))
    or public.is_call_participant(secondary_call_id, (select auth.uid()))
  );

grant select on public.call_merge_operations to authenticated;

-- Add call_merge_operations to Supabase Realtime publication idempotently
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'call_merge_operations'
  ) then
    alter publication supabase_realtime add table public.call_merge_operations;
  end if;
end;
$$;

-- 3. Phase A: prepare_call_merge RPC
create or replace function public.prepare_call_merge(
  p_primary_call_id uuid,
  p_secondary_call_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = '' as $$
declare
  v_user_uid uuid := auth.uid();
  v_primary_call public.calls%rowtype;
  v_secondary_call public.calls%rowtype;
  v_joining_user_uid uuid;
  v_distinct_count int;
  v_existing_op public.call_merge_operations%rowtype;
  v_merge_op_id uuid;
  v_expires_at timestamptz;
begin
  if v_user_uid is null then
    raise exception 'Authentication required';
  end if;

  if p_primary_call_id is null or p_secondary_call_id is null then
    raise exception 'Call IDs cannot be null';
  end if;

  if p_primary_call_id = p_secondary_call_id then
    raise exception 'Primary and secondary call IDs must be distinct';
  end if;

  -- 1. Deterministic row locking by call UUID to prevent concurrent deadlocks
  perform 1
  from public.calls
  where id in (p_primary_call_id, p_secondary_call_id)
  order by id
  for update;

  select * into v_primary_call from public.calls where id = p_primary_call_id;
  select * into v_secondary_call from public.calls where id = p_secondary_call_id;

  if v_primary_call.id is null or v_secondary_call.id is null then
    return jsonb_build_object('result', 'rejected', 'reason', 'call_not_found');
  end if;

  -- 2. Validate calls are in non-terminal active states
  if v_primary_call.status not in ('connected', 'on_hold') or
     v_secondary_call.status not in ('connected', 'on_hold') then
    return jsonb_build_object('result', 'rejected', 'reason', 'calls_not_active');
  end if;

  -- 3. Validate initiator participates in both calls
  if not exists (
    select 1 from public.call_participants
    where call_id = p_primary_call_id and user_uid = v_user_uid and left_at is null
  ) or not exists (
    select 1 from public.call_participants
    where call_id = p_secondary_call_id and user_uid = v_user_uid and left_at is null
  ) then
    return jsonb_build_object('result', 'rejected', 'reason', 'unauthorized_participant');
  end if;

  -- 4. Identify migrating secondary participant (User C)
  select user_uid into v_joining_user_uid
  from public.call_participants
  where call_id = p_secondary_call_id and user_uid <> v_user_uid and left_at is null
  limit 1;

  if v_joining_user_uid is null then
    return jsonb_build_object('result', 'rejected', 'reason', 'no_secondary_participant');
  end if;

  -- Reject if migrating participant is already an active participant in primary call
  if exists (
    select 1 from public.call_participants
    where call_id = p_primary_call_id and user_uid = v_joining_user_uid and left_at is null
  ) then
    return jsonb_build_object('result', 'rejected', 'reason', 'participant_already_in_primary');
  end if;

  -- 5. Enforce participant capacity limit (canonical limit: 8)
  select count(distinct user_uid) into v_distinct_count
  from public.call_participants
  where call_id in (p_primary_call_id, p_secondary_call_id) and left_at is null;

  if v_distinct_count > 8 then
    return jsonb_build_object('result', 'rejected', 'reason', 'capacity_exceeded');
  end if;

  -- 6. Idempotency: return active prepared/joining operation if valid and non-expired
  select * into v_existing_op
  from public.call_merge_operations
  where primary_call_id = p_primary_call_id
    and secondary_call_id = p_secondary_call_id
    and status in ('prepared', 'joining')
    and expires_at > clock_timestamp();

  if v_existing_op.id is not null then
    return jsonb_build_object(
      'result', 'already_prepared',
      'merge_operation_id', v_existing_op.id,
      'primary_call_id', v_existing_op.primary_call_id,
      'secondary_call_id', v_existing_op.secondary_call_id,
      'joining_user_uid', v_existing_op.joining_user_uid,
      'status', v_existing_op.status,
      'expires_at', v_existing_op.expires_at
    );
  end if;

  -- Mark previously expired operations for this pair as expired
  update public.call_merge_operations
  set status = 'expired'
  where primary_call_id = p_primary_call_id
    and secondary_call_id = p_secondary_call_id
    and status in ('prepared', 'joining')
    and expires_at <= clock_timestamp();

  -- 7. Insert new merge operation with 30-second TTL
  v_expires_at := clock_timestamp() + interval '30 seconds';
  insert into public.call_merge_operations (
    primary_call_id,
    secondary_call_id,
    initiated_by,
    joining_user_uid,
    status,
    expires_at
  ) values (
    p_primary_call_id,
    p_secondary_call_id,
    v_user_uid,
    v_joining_user_uid,
    'prepared',
    v_expires_at
  )
  returning id into v_merge_op_id;

  return jsonb_build_object(
    'result', 'prepared',
    'merge_operation_id', v_merge_op_id,
    'primary_call_id', p_primary_call_id,
    'secondary_call_id', p_secondary_call_id,
    'joining_user_uid', v_joining_user_uid,
    'status', 'prepared',
    'expires_at', v_expires_at
  );
end;
$$;

revoke all on function public.prepare_call_merge(uuid, uuid) from public;
grant execute on function public.prepare_call_merge(uuid, uuid) to authenticated;

-- 4. Phase C: commit_call_merge RPC
-- CRITICAL SECURITY: Normal authenticated clients CANNOT execute commit_call_merge directly.
-- Execution is restricted to trusted server/service execution (service_role).
create or replace function public.commit_call_merge(
  p_merge_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = '' as $$
declare
  v_op public.call_merge_operations%rowtype;
  v_primary_call public.calls%rowtype;
  v_secondary_call public.calls%rowtype;
  v_distinct_count int;
  v_now timestamptz := clock_timestamp();
begin
  if p_merge_operation_id is null then
    raise exception 'Merge operation ID cannot be null';
  end if;

  -- 1. Lock merge operation
  select * into v_op
  from public.call_merge_operations
  where id = p_merge_operation_id
  for update;

  if v_op.id is null then
    return jsonb_build_object('result', 'rejected', 'reason', 'merge_op_not_found');
  end if;

  -- Idempotent return if already committed
  if v_op.status = 'committed' then
    return jsonb_build_object(
      'result', 'already_committed',
      'conference_call_id', v_op.primary_call_id,
      'committed_at', v_op.committed_at
    );
  end if;

  -- Reject if expired or cancelled
  if v_op.status in ('cancelled', 'expired') or v_op.expires_at <= v_now then
    if v_op.status not in ('cancelled', 'expired') then
      update public.call_merge_operations
      set status = 'expired'
      where id = p_merge_operation_id;
    end if;
    return jsonb_build_object('result', 'rejected', 'reason', 'merge_op_expired_or_cancelled');
  end if;

  if v_op.status not in ('prepared', 'joining') then
    return jsonb_build_object('result', 'rejected', 'reason', 'invalid_operation_state');
  end if;

  -- 2. Lock both calls deterministically
  perform 1
  from public.calls
  where id in (v_op.primary_call_id, v_op.secondary_call_id)
  order by id
  for update;

  select * into v_primary_call from public.calls where id = v_op.primary_call_id;
  select * into v_secondary_call from public.calls where id = v_op.secondary_call_id;

  if v_primary_call.id is null or v_secondary_call.id is null then
    return jsonb_build_object('result', 'rejected', 'reason', 'call_not_found');
  end if;

  if v_primary_call.status in ('completed', 'cancelled', 'failed', 'declined', 'missed') or
     v_secondary_call.status in ('completed', 'cancelled', 'failed', 'declined', 'missed') then
    return jsonb_build_object('result', 'rejected', 'reason', 'calls_terminated');
  end if;

  -- 3. Re-verify participants
  if not exists (
    select 1 from public.call_participants
    where call_id = v_op.primary_call_id and user_uid = v_op.initiated_by and left_at is null
  ) then
    return jsonb_build_object('result', 'rejected', 'reason', 'initiator_left_primary');
  end if;

  if not exists (
    select 1 from public.call_participants
    where call_id = v_op.secondary_call_id and user_uid = v_op.joining_user_uid and left_at is null
  ) then
    return jsonb_build_object('result', 'rejected', 'reason', 'joining_user_left_secondary');
  end if;

  -- Re-verify conference participant capacity
  select count(distinct user_uid) into v_distinct_count
  from public.call_participants
  where (call_id = v_op.primary_call_id or (call_id = v_op.secondary_call_id and user_uid = v_op.joining_user_uid))
    and left_at is null;

  if v_distinct_count > 8 then
    return jsonb_build_object('result', 'rejected', 'reason', 'capacity_exceeded');
  end if;

  -- 4. Atomically migrate joining participant into primary call
  insert into public.call_participants (
    call_id,
    user_uid,
    joined_at,
    muted,
    camera_enabled
  ) values (
    v_op.primary_call_id,
    v_op.joining_user_uid,
    v_now,
    false,
    (v_secondary_call.call_type = 'video')
  )
  on conflict (call_id, user_uid) do update
    set left_at = null,
        camera_enabled = excluded.camera_enabled;

  -- 5. Clear hold state on primary call and mark connected
  update public.calls
  set status = 'connected',
      held_by = null
  where id = v_op.primary_call_id;

  -- 6. Atomically close secondary call and set merged_into_call_id
  update public.calls
  set status = 'completed',
      ended_at = v_now,
      ended_reason = 'merged',
      merged_into_call_id = v_op.primary_call_id
  where id = v_op.secondary_call_id;

  update public.call_participants
  set left_at = v_now
  where call_id = v_op.secondary_call_id
    and left_at is null;

  -- 7. Update merge operation to committed
  update public.call_merge_operations
  set status = 'committed',
      committed_at = v_now
  where id = p_merge_operation_id;

  return jsonb_build_object(
    'result', 'committed',
    'conference_call_id', v_op.primary_call_id,
    'secondary_call_id', v_op.secondary_call_id,
    'joining_user_uid', v_op.joining_user_uid,
    'committed_at', v_now
  );
end;
$$;

-- Security: Revoke commit_call_merge from all public/anon/authenticated users.
-- Only service_role (trusted edge function / server) may execute commit.
revoke all on function public.commit_call_merge(uuid) from public, anon, authenticated;
grant execute on function public.commit_call_merge(uuid) to service_role;

-- 5. Rollback RPC: cancel_call_merge
create or replace function public.cancel_call_merge(
  p_merge_operation_id uuid,
  p_reason text default 'client_aborted'
)
returns jsonb
language plpgsql
security definer
set search_path = '' as $$
declare
  v_user_uid uuid := auth.uid();
  v_op public.call_merge_operations%rowtype;
begin
  if v_user_uid is null then
    raise exception 'Authentication required';
  end if;

  if p_merge_operation_id is null then
    raise exception 'Merge operation ID cannot be null';
  end if;

  -- Lock merge operation
  select * into v_op
  from public.call_merge_operations
  where id = p_merge_operation_id
  for update;

  if v_op.id is null then
    return jsonb_build_object('result', 'rejected', 'reason', 'merge_op_not_found');
  end if;

  -- If already committed, return rejected safely
  if v_op.status = 'committed' then
    return jsonb_build_object(
      'result', 'rejected',
      'reason', 'already_committed',
      'conference_call_id', v_op.primary_call_id
    );
  end if;

  -- If already cancelled, return idempotent result
  if v_op.status = 'cancelled' then
    return jsonb_build_object(
      'result', 'already_cancelled',
      'merge_operation_id', v_op.id
    );
  end if;

  -- Validate initiator authority
  if v_op.initiated_by <> v_user_uid then
    return jsonb_build_object('result', 'rejected', 'reason', 'unauthorized_initiator');
  end if;

  -- Mark cancelled
  update public.call_merge_operations
  set status = 'cancelled',
      cancelled_at = clock_timestamp()
  where id = p_merge_operation_id;

  return jsonb_build_object(
    'result', 'cancelled',
    'merge_operation_id', v_op.id,
    'reason', coalesce(p_reason, 'client_aborted')
  );
end;
$$;

revoke all on function public.cancel_call_merge(uuid, text) from public;
grant execute on function public.cancel_call_merge(uuid, text) to authenticated;

-- 6. Recents query reconciliation
create or replace function public.list_my_recent_calls()
returns table (
  id uuid, other_uid uuid, display_name text, voryn_id text, call_type text,
  direction text, status text, created_at timestamptz, answered_at timestamptz, ended_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select 
    c.id,
    case when count(distinct other.user_uid) > 1 then null else min(other.user_uid::text)::uuid end as other_uid,
    case 
      when count(distinct other.user_uid) > 1 then 'Conference (' || (count(distinct other.user_uid) + 1) || ')'
      else max(p.full_name)
    end as display_name,
    case when count(distinct other.user_uid) > 1 then '@conference' else max(p.voryn_id) end as voryn_id,
    c.call_type,
    case when c.initiated_by = auth.uid() then 'outgoing' else 'incoming' end as direction,
    c.status,
    c.created_at,
    c.answered_at,
    c.ended_at
  from public.calls c
  join public.call_participants mine on mine.call_id = c.id and mine.user_uid = auth.uid()
  left join public.call_participants other on other.call_id = c.id and other.user_uid <> auth.uid()
  left join public.profiles p on p.uid = other.user_uid
  where c.merged_into_call_id is null
  group by c.id, c.call_type, c.initiated_by, c.status, c.created_at, c.answered_at, c.ended_at
  order by c.created_at desc
  limit 200;
$$;

revoke all on function public.list_my_recent_calls() from public;
grant execute on function public.list_my_recent_calls() to authenticated;
