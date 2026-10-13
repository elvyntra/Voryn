-- Migration: 202610090002_call_audio_to_video_upgrade
-- Description: In-call Audio-to-Video upgrade negotiation with receiver approval
-- Checkpoint: CALL-AV-1

-- 1. Create public.call_video_upgrade_requests table
create table if not exists public.call_video_upgrade_requests (
  id uuid primary key default gen_random_uuid(),
  call_id uuid not null references public.calls(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  target_user_uid uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'cancelled', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 seconds'),
  responded_at timestamptz,
  constraint call_video_upgrade_distinct_users check (requested_by <> target_user_uid)
);

-- Indexes for efficient lookup
create index if not exists idx_call_video_upgrade_call_id
  on public.call_video_upgrade_requests(call_id);

create index if not exists idx_call_video_upgrade_active
  on public.call_video_upgrade_requests(call_id, target_user_uid, status)
  where status = 'pending';

-- 2. Enable Row-Level Security
alter table public.call_video_upgrade_requests enable row level security;

drop policy if exists "call_video_upgrade_requests_select" on public.call_video_upgrade_requests;
create policy "call_video_upgrade_requests_select" on public.call_video_upgrade_requests
  for select to authenticated
  using (
    requested_by = (select auth.uid())
    or target_user_uid = (select auth.uid())
    or public.is_call_participant(call_id, (select auth.uid()))
  );

grant select on public.call_video_upgrade_requests to authenticated;

-- Add to Realtime publication idempotently
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'call_video_upgrade_requests'
  ) then
    alter publication supabase_realtime add table public.call_video_upgrade_requests;
  end if;
end;
$$;

-- 3. RPC: request_video_upgrade
create or replace function public.request_video_upgrade(
  p_call_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = '' as $$
declare
  v_user_uid uuid := auth.uid();
  v_call public.calls%rowtype;
  v_target_user_uid uuid;
  v_existing_peer_req public.call_video_upgrade_requests%rowtype;
  v_existing_my_req public.call_video_upgrade_requests%rowtype;
  v_new_req public.call_video_upgrade_requests%rowtype;
begin
  if v_user_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthenticated');
  end if;

  if not public.is_call_participant(p_call_id, v_user_uid) then
    return jsonb_build_object('ok', false, 'error', 'Caller is not a participant in this call');
  end if;

  select * into v_call from public.calls where id = p_call_id;
  if v_call.id is null then
    return jsonb_build_object('ok', false, 'error', 'Call not found');
  end if;

  if v_call.status <> 'connected' then
    return jsonb_build_object('ok', false, 'error', 'Call is not currently active');
  end if;

  if v_call.call_type = 'video' then
    return jsonb_build_object('ok', true, 'status', 'already_video');
  end if;

  -- Identify other participant in 1-to-1 call
  select user_uid into v_target_user_uid
  from public.call_participants
  where call_id = p_call_id and user_uid <> v_user_uid
  limit 1;

  if v_target_user_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Remote participant not found');
  end if;

  -- Simultaneous request handling: if the peer also sent an unexpired pending request, coalesce into accept
  select * into v_existing_peer_req
  from public.call_video_upgrade_requests
  where call_id = p_call_id
    and requested_by = v_target_user_uid
    and status = 'pending'
    and expires_at > now()
  order by created_at desc
  limit 1;

  if v_existing_peer_req.id is not null then
    update public.call_video_upgrade_requests
    set status = 'accepted', responded_at = now()
    where id = v_existing_peer_req.id;

    update public.calls
    set call_type = 'video'
    where id = p_call_id;

    return jsonb_build_object(
      'ok', true,
      'status', 'accepted',
      'request_id', v_existing_peer_req.id,
      'coalesced', true
    );
  end if;

  -- If caller already has an unexpired pending request for this call, return it
  select * into v_existing_my_req
  from public.call_video_upgrade_requests
  where call_id = p_call_id
    and requested_by = v_user_uid
    and status = 'pending'
    and expires_at > now()
  order by created_at desc
  limit 1;

  if v_existing_my_req.id is not null then
    return jsonb_build_object(
      'ok', true,
      'status', 'pending',
      'request_id', v_existing_my_req.id,
      'expires_at', v_existing_my_req.expires_at,
      'already_pending', true
    );
  end if;

  -- Mark any old/stale requests on this call as expired
  update public.call_video_upgrade_requests
  set status = 'expired'
  where call_id = p_call_id and status = 'pending' and expires_at <= now();

  -- Insert new upgrade request
  insert into public.call_video_upgrade_requests (
    call_id, requested_by, target_user_uid, status, expires_at
  ) values (
    p_call_id, v_user_uid, v_target_user_uid, 'pending', now() + interval '30 seconds'
  )
  returning * into v_new_req;

  return jsonb_build_object(
    'ok', true,
    'status', 'pending',
    'request_id', v_new_req.id,
    'target_user_uid', v_target_user_uid,
    'expires_at', v_new_req.expires_at
  );
end;
$$;

-- 4. RPC: respond_video_upgrade
create or replace function public.respond_video_upgrade(
  p_request_id uuid,
  p_accept boolean
)
returns jsonb
language plpgsql
security definer
set search_path = '' as $$
declare
  v_user_uid uuid := auth.uid();
  v_req public.call_video_upgrade_requests%rowtype;
  v_call_status text;
begin
  if v_user_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthenticated');
  end if;

  select * into v_req
  from public.call_video_upgrade_requests
  where id = p_request_id;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'Request not found');
  end if;

  if v_req.target_user_uid <> v_user_uid then
    return jsonb_build_object('ok', false, 'error', 'Only the designated recipient can respond to this request');
  end if;

  if v_req.status <> 'pending' or v_req.expires_at <= now() then
    if v_req.status = 'pending' then
      update public.call_video_upgrade_requests
      set status = 'expired'
      where id = p_request_id;
    end if;
    return jsonb_build_object(
      'ok', false,
      'error', 'Request is expired or already resolved',
      'status', v_req.status
    );
  end if;

  select status into v_call_status
  from public.calls
  where id = v_req.call_id;

  if v_call_status <> 'connected' then
    update public.call_video_upgrade_requests
    set status = 'cancelled', responded_at = now()
    where id = p_request_id;
    return jsonb_build_object('ok', false, 'error', 'Call is no longer active');
  end if;

  if p_accept then
    update public.call_video_upgrade_requests
    set status = 'accepted', responded_at = now()
    where id = p_request_id;

    update public.calls
    set call_type = 'video'
    where id = v_req.call_id;

    return jsonb_build_object(
      'ok', true,
      'status', 'accepted',
      'call_id', v_req.call_id
    );
  else
    update public.call_video_upgrade_requests
    set status = 'declined', responded_at = now()
    where id = p_request_id;

    return jsonb_build_object(
      'ok', true,
      'status', 'declined',
      'call_id', v_req.call_id
    );
  end if;
end;
$$;

-- 5. RPC: cancel_video_upgrade
create or replace function public.cancel_video_upgrade(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = '' as $$
declare
  v_user_uid uuid := auth.uid();
  v_req public.call_video_upgrade_requests%rowtype;
begin
  if v_user_uid is null then
    return jsonb_build_object('ok', false, 'error', 'Unauthenticated');
  end if;

  select * into v_req
  from public.call_video_upgrade_requests
  where id = p_request_id;

  if v_req.id is null then
    return jsonb_build_object('ok', false, 'error', 'Request not found');
  end if;

  if v_req.requested_by <> v_user_uid then
    return jsonb_build_object('ok', false, 'error', 'Only the requester can cancel this request');
  end if;

  if v_req.status <> 'pending' then
    return jsonb_build_object('ok', true, 'status', v_req.status, 'already_resolved', true);
  end if;

  update public.call_video_upgrade_requests
  set status = 'cancelled', responded_at = now()
  where id = p_request_id;

  return jsonb_build_object('ok', true, 'status', 'cancelled');
end;
$$;

-- 6. RPC: get_active_video_upgrade_request
create or replace function public.get_active_video_upgrade_request(
  p_call_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = '' as $$
declare
  v_user_uid uuid := auth.uid();
  v_req public.call_video_upgrade_requests%rowtype;
begin
  if v_user_uid is null then
    return null;
  end if;

  if not public.is_call_participant(p_call_id, v_user_uid) then
    return null;
  end if;

  select * into v_req
  from public.call_video_upgrade_requests
  where call_id = p_call_id
    and status = 'pending'
    and expires_at > now()
  order by created_at desc
  limit 1;

  if v_req.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'id', v_req.id,
    'call_id', v_req.call_id,
    'requested_by', v_req.requested_by,
    'target_user_uid', v_req.target_user_uid,
    'status', v_req.status,
    'created_at', v_req.created_at,
    'expires_at', v_req.expires_at,
    'is_requester', (v_req.requested_by = v_user_uid),
    'is_recipient', (v_req.target_user_uid = v_user_uid)
  );
end;
$$;

-- 7. Grant execute permissions to authenticated
revoke all on function public.request_video_upgrade(uuid) from public;
grant execute on function public.request_video_upgrade(uuid) to authenticated;

revoke all on function public.respond_video_upgrade(uuid, boolean) from public;
grant execute on function public.respond_video_upgrade(uuid, boolean) to authenticated;

revoke all on function public.cancel_video_upgrade(uuid) from public;
grant execute on function public.cancel_video_upgrade(uuid) to authenticated;

revoke all on function public.get_active_video_upgrade_request(uuid) from public;
grant execute on function public.get_active_video_upgrade_request(uuid) to authenticated;

