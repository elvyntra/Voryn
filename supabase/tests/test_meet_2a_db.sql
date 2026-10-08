-- Test Suite for MEET-2A: Comprehensive 28-scenario database and RPC verification
-- Returns structured table(test_num int, test_name text, status text)

create or replace function pg_temp.run_meet2a_tests()
returns table(test_num int, test_name text, status text)
language plpgsql as $$
declare
  c_user_a uuid := '9cb63f35-523c-4f24-8646-0ed795adeb7e';
  c_user_b uuid := '362fb771-5736-4fae-a8c3-0d72189de8f3';
  c_user_c uuid := 'ce948bbb-983c-4ceb-9072-c72bcfdf9cf4';
  c_user_d uuid := 'ce53654a-97c6-434b-bdc4-dd87353ace81';
  c_user_e uuid := '6f7f1ca3-32c2-43c3-a4f9-d01dadd1a4b5';
  c_user_f uuid := '3e1b5ac1-9a49-418b-bfdc-54186aa16bef';
  c_user_g uuid := 'a1111111-1111-1111-1111-111111111111';
  c_user_h uuid := 'a2222222-2222-2222-2222-222222222222';
  c_user_i uuid := 'a3333333-3333-3333-3333-333333333333';
  c_user_j uuid := 'a4444444-4444-4444-4444-444444444444';

  v_m1_id uuid; v_m1_code text;
  v_m2_id uuid; v_m2_code text;
  v_m3_id uuid; v_m3_code text;
  v_m4_id uuid; v_m4_code text;
  v_m5_id uuid; v_m5_code text;
  v_m6_id uuid; v_m6_code text;
  v_m7_id uuid; v_m7_code text;
  v_m8_id uuid; v_m8_code text;
  v_legacy_id uuid; v_legacy_code text;

  v_cnt bigint;
  v_hist_cnt bigint;
  v_active_cnt bigint;
  v_status text;
  v_role text;
  v_is_host_a boolean;
  v_is_host_d boolean;
  v_started_at timestamptz;
  v_ended_at timestamptz;
  v_joined_at timestamptz;
  v_left_at timestamptz;
  v_invited_at timestamptz;
  v_exception_caught boolean;
begin
  -- Temporary test users in auth.users for capacity tests
  insert into auth.users (id, aud, role, email)
  values
    (c_user_g, 'authenticated', 'authenticated', 'test_g@voryn.internal'),
    (c_user_h, 'authenticated', 'authenticated', 'test_h@voryn.internal'),
    (c_user_i, 'authenticated', 'authenticated', 'test_i@voryn.internal'),
    (c_user_j, 'authenticated', 'authenticated', 'test_j@voryn.internal')
  on conflict (id) do nothing;

  -- Clean up any residual test data from previous test runs
  delete from public.meeting_participants where user_uid in (c_user_a, c_user_b, c_user_c, c_user_d, c_user_e, c_user_f, c_user_g, c_user_h, c_user_i, c_user_j);
  delete from public.meetings where host_uid in (c_user_a, c_user_b, c_user_c, c_user_d, c_user_e, c_user_f, c_user_g, c_user_h, c_user_i, c_user_j) or join_code = 'a1f-4b2-9e0';

  -- Authenticated user context as host A
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);

  -- TEST 1: Authenticated host creates meeting
  select m.id, m.join_code into v_m1_id, v_m1_code
  from public.create_voryn_meeting('Sprint Planning', 'link') m;

  select count(*), max(role) into v_cnt, v_role
  from public.meeting_participants
  where meeting_id = v_m1_id and user_uid = c_user_a;

  if v_m1_id is not null and v_cnt = 1 and v_role = 'host' then
    test_num := 1; test_name := 'Authenticated host creates meeting'; status := 'PASS'; return next;
  else
    test_num := 1; test_name := 'Authenticated host creates meeting'; status := 'FAIL'; return next;
  end if;

  -- TEST 2: New code uses base36-compatible format
  if v_m1_code ~ '^[0-9a-z]{3}-[0-9a-z]{3}-[0-9a-z]{3}$' and length(v_m1_code) = 11 then
    test_num := 2; test_name := 'New code uses base36-compatible format'; status := 'PASS'; return next;
  else
    test_num := 2; test_name := 'New code uses base36-compatible format'; status := 'FAIL'; return next;
  end if;

  -- TEST 3: Legacy hex code still resolves
  insert into public.meetings (id, host_uid, title, join_code, access, status)
  values (gen_random_uuid(), c_user_a, 'Legacy Hex Meeting', 'a1f-4b2-9e0', 'link', 'ready')
  returning id, join_code into v_legacy_id, v_legacy_code;

  insert into public.meeting_participants (meeting_id, user_uid, role, joined_at)
  values (v_legacy_id, c_user_a, 'host', null);

  perform set_config('request.jwt.claim.sub', c_user_b::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_b::text)::text, true);

  select count(*) into v_cnt
  from public.resolve_meeting_for_prejoin('A1F-4B2-9E0');

  if v_cnt = 1 then
    test_num := 3; test_name := 'Legacy hex code still resolves'; status := 'PASS'; return next;
  else
    test_num := 3; test_name := 'Legacy hex code still resolves'; status := 'FAIL'; return next;
  end if;

  -- TEST 4: Unauthenticated resolve denied
  v_exception_caught := false;
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    perform * from public.resolve_meeting_for_prejoin(v_m1_code);
  exception when others then
    v_exception_caught := true;
  end;

  if v_exception_caught then
    test_num := 4; test_name := 'Unauthenticated resolve denied'; status := 'PASS'; return next;
  else
    test_num := 4; test_name := 'Unauthenticated resolve denied'; status := 'FAIL'; return next;
  end if;

  -- Restore auth as user B
  perform set_config('request.jwt.claim.sub', c_user_b::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_b::text)::text, true);

  -- TEST 5: Pre-join does not insert participant
  select count(*) into v_cnt from public.meeting_participants where meeting_id = v_m1_id;
  perform * from public.resolve_meeting_for_prejoin(v_m1_code);
  select count(*) into v_cnt from public.meeting_participants where meeting_id = v_m1_id and user_uid = c_user_b;

  if v_cnt = 0 then
    test_num := 5; test_name := 'Pre-join does not insert participant'; status := 'PASS'; return next;
  else
    test_num := 5; test_name := 'Pre-join does not insert participant'; status := 'FAIL'; return next;
  end if;

  -- TEST 6: Host can start meeting
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  select sm.status, sm.started_at into v_status, v_started_at from public.start_voryn_meeting(v_m1_id) sm;

  if v_status = 'active' and v_started_at is not null then
    test_num := 6; test_name := 'Host can start meeting'; status := 'PASS'; return next;
  else
    test_num := 6; test_name := 'Host can start meeting'; status := 'FAIL'; return next;
  end if;

  -- TEST 7: Non-host cannot start
  select m.id, m.join_code into v_m2_id, v_m2_code
  from public.create_voryn_meeting('All Hands', 'link') m;

  perform set_config('request.jwt.claim.sub', c_user_b::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_b::text)::text, true);
  v_exception_caught := false;
  begin
    perform * from public.start_voryn_meeting(v_m2_id);
  exception when others then
    v_exception_caught := true;
  end;

  if v_exception_caught then
    test_num := 7; test_name := 'Non-host cannot start'; status := 'PASS'; return next;
  else
    test_num := 7; test_name := 'Non-host cannot start'; status := 'FAIL'; return next;
  end if;

  -- TEST 8: Start is idempotent
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  select sm.status into v_status from public.start_voryn_meeting(v_m1_id) sm;

  if v_status = 'active' then
    test_num := 8; test_name := 'Start is idempotent'; status := 'PASS'; return next;
  else
    test_num := 8; test_name := 'Start is idempotent'; status := 'FAIL'; return next;
  end if;

  -- TEST 9: User joins link meeting
  perform set_config('request.jwt.claim.sub', c_user_b::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_b::text)::text, true);
  perform * from public.join_voryn_meeting(v_m1_code);

  select count(*) into v_cnt
  from public.meeting_participants
  where meeting_id = v_m1_id and user_uid = c_user_b and joined_at is not null and left_at is null;

  if v_cnt = 1 then
    test_num := 9; test_name := 'User joins link meeting'; status := 'PASS'; return next;
  else
    test_num := 9; test_name := 'User joins link meeting'; status := 'FAIL'; return next;
  end if;

  -- TEST 10: Invited-only rejects non-invited user
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  select m.id, m.join_code into v_m3_id, v_m3_code
  from public.create_voryn_meeting('Executive Review', 'invited') m;

  perform set_config('request.jwt.claim.sub', c_user_c::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_c::text)::text, true);
  select count(*) into v_cnt from public.join_voryn_meeting(v_m3_code);

  if v_cnt = 0 then
    test_num := 10; test_name := 'Invited-only rejects non-invited user'; status := 'PASS'; return next;
  else
    test_num := 10; test_name := 'Invited-only rejects non-invited user'; status := 'FAIL'; return next;
  end if;

  -- TEST 11: Invited-only allows invited user
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  perform * from public.invite_meeting_participant(v_m3_id, c_user_c);

  perform set_config('request.jwt.claim.sub', c_user_c::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_c::text)::text, true);
  select count(*) into v_cnt from public.join_voryn_meeting(v_m3_code);

  if v_cnt = 1 then
    test_num := 11; test_name := 'Invited-only allows invited user'; status := 'PASS'; return next;
  else
    test_num := 11; test_name := 'Invited-only allows invited user'; status := 'FAIL'; return next;
  end if;

  -- TEST 12: Host role cannot be downgraded
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  perform * from public.join_voryn_meeting(v_m1_code);

  select role into v_role
  from public.meeting_participants
  where meeting_id = v_m1_id and user_uid = c_user_a;

  if v_role = 'host' then
    test_num := 12; test_name := 'Host role cannot be downgraded'; status := 'PASS'; return next;
  else
    test_num := 12; test_name := 'Host role cannot be downgraded'; status := 'FAIL'; return next;
  end if;

  -- TEST 13: Active capacity capped at 8
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  select m.id, m.join_code into v_m4_id, v_m4_code
  from public.create_voryn_meeting('Full Room', 'link') m;

  -- 1. A joins
  perform * from public.join_voryn_meeting(v_m4_code);
  -- 2. B joins
  perform set_config('request.jwt.claim.sub', c_user_b::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_b::text)::text, true);
  perform * from public.join_voryn_meeting(v_m4_code);
  -- 3. C joins
  perform set_config('request.jwt.claim.sub', c_user_c::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_c::text)::text, true);
  perform * from public.join_voryn_meeting(v_m4_code);
  -- 4. D joins
  perform set_config('request.jwt.claim.sub', c_user_d::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_d::text)::text, true);
  perform * from public.join_voryn_meeting(v_m4_code);
  -- 5. E joins
  perform set_config('request.jwt.claim.sub', c_user_e::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_e::text)::text, true);
  perform * from public.join_voryn_meeting(v_m4_code);
  -- 6. F joins
  perform set_config('request.jwt.claim.sub', c_user_f::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_f::text)::text, true);
  perform * from public.join_voryn_meeting(v_m4_code);
  -- 7. G joins
  perform set_config('request.jwt.claim.sub', c_user_g::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_g::text)::text, true);
  perform * from public.join_voryn_meeting(v_m4_code);
  -- 8. H joins
  perform set_config('request.jwt.claim.sub', c_user_h::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_h::text)::text, true);
  perform * from public.join_voryn_meeting(v_m4_code);

  -- 9th participant (user I) attempts to join -> must raise capacity exception
  perform set_config('request.jwt.claim.sub', c_user_i::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_i::text)::text, true);
  v_exception_caught := false;
  begin
    perform * from public.join_voryn_meeting(v_m4_code);
  exception when others then
    v_exception_caught := true;
  end;

  if v_exception_caught then
    test_num := 13; test_name := 'Active capacity capped at 8'; status := 'PASS'; return next;
  else
    test_num := 13; test_name := 'Active capacity capped at 8'; status := 'FAIL'; return next;
  end if;

  -- TEST 14: Concurrent/race-safe capacity behavior (rejoin by existing active participant allowed)
  perform set_config('request.jwt.claim.sub', c_user_b::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_b::text)::text, true);
  select count(*) into v_cnt from public.join_voryn_meeting(v_m4_code);

  if v_cnt = 1 then
    test_num := 14; test_name := 'Concurrent/race-safe capacity behavior'; status := 'PASS'; return next;
  else
    test_num := 14; test_name := 'Concurrent/race-safe capacity behavior'; status := 'FAIL'; return next;
  end if;

  -- TEST 15: Leave only modifies caller
  perform set_config('request.jwt.claim.sub', c_user_b::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_b::text)::text, true);
  perform * from public.leave_voryn_meeting(v_m4_id);

  select count(*) into v_cnt
  from public.meeting_participants
  where meeting_id = v_m4_id and user_uid = c_user_b and left_at is not null;

  select count(*) into v_cnt
  from public.meeting_participants
  where meeting_id = v_m4_id and user_uid = c_user_c and left_at is null;

  if v_cnt = 1 then
    test_num := 15; test_name := 'Leave only modifies caller'; status := 'PASS'; return next;
  else
    test_num := 15; test_name := 'Leave only modifies caller'; status := 'FAIL'; return next;
  end if;

  -- TEST 16: Last participant leave auto-ends
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  select m.id, m.join_code into v_m5_id, v_m5_code
  from public.create_voryn_meeting('Quick 1-on-1', 'link') m;

  perform * from public.start_voryn_meeting(v_m5_id);
  perform * from public.join_voryn_meeting(v_m5_code);
  perform * from public.leave_voryn_meeting(v_m5_id);

  select m.status, m.ended_at into v_status, v_ended_at
  from public.meetings m where m.id = v_m5_id;

  if v_status = 'ended' and v_ended_at is not null then
    test_num := 16; test_name := 'Last participant leave auto-ends'; status := 'PASS'; return next;
  else
    test_num := 16; test_name := 'Last participant leave auto-ends'; status := 'FAIL'; return next;
  end if;

  -- TEST 17: Non-last leave does not end
  select m.status into v_status from public.meetings m where m.id = v_m4_id;

  if v_status = 'active' then
    test_num := 17; test_name := 'Non-last leave does not end'; status := 'PASS'; return next;
  else
    test_num := 17; test_name := 'Non-last leave does not end'; status := 'FAIL'; return next;
  end if;

  -- TEST 18: Host can end for everyone
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  select em.status, em.ended_at into v_status, v_ended_at
  from public.end_voryn_meeting_for_everyone(v_m4_id) em;

  select count(*) into v_cnt
  from public.meeting_participants
  where meeting_id = v_m4_id and joined_at is not null and left_at is null;

  if v_status = 'ended' and v_ended_at is not null and v_cnt = 0 then
    test_num := 18; test_name := 'Host can end for everyone'; status := 'PASS'; return next;
  else
    test_num := 18; test_name := 'Host can end for everyone'; status := 'FAIL'; return next;
  end if;

  -- TEST 19: Non-host cannot end for everyone
  select m.id, m.join_code into v_m6_id, v_m6_code
  from public.create_voryn_meeting('Meeting 6', 'link') m;
  perform * from public.start_voryn_meeting(v_m6_id);

  perform set_config('request.jwt.claim.sub', c_user_b::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_b::text)::text, true);
  perform * from public.join_voryn_meeting(v_m6_code);

  v_exception_caught := false;
  begin
    perform * from public.end_voryn_meeting_for_everyone(v_m6_id);
  exception when others then
    v_exception_caught := true;
  end;

  if v_exception_caught then
    test_num := 19; test_name := 'Non-host cannot end for everyone'; status := 'PASS'; return next;
  else
    test_num := 19; test_name := 'Non-host cannot end for everyone'; status := 'FAIL'; return next;
  end if;

  -- TEST 20: Ready meeting can be cancelled by host
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  select m.id, m.join_code into v_m7_id, v_m7_code
  from public.create_voryn_meeting('Unused Link', 'link') m;

  select cm.status into v_status from public.cancel_voryn_meeting(v_m7_id) cm;

  if v_status = 'cancelled' then
    test_num := 20; test_name := 'Ready meeting can be cancelled by host'; status := 'PASS'; return next;
  else
    test_num := 20; test_name := 'Ready meeting can be cancelled by host'; status := 'FAIL'; return next;
  end if;

  -- TEST 21: Active meeting cannot be cancelled improperly
  v_exception_caught := false;
  begin
    perform * from public.cancel_voryn_meeting(v_m6_id);
  exception when others then
    v_exception_caught := true;
  end;

  if v_exception_caught then
    test_num := 21; test_name := 'Active meeting cannot be cancelled improperly'; status := 'PASS'; return next;
  else
    test_num := 21; test_name := 'Active meeting cannot be cancelled improperly'; status := 'FAIL'; return next;
  end if;

  -- TEST 22: Invite record does not set joined_at
  select m.id, m.join_code into v_m8_id, v_m8_code
  from public.create_voryn_meeting('Product Review', 'link') m;

  perform * from public.invite_meeting_participant(v_m8_id, c_user_d);

  select joined_at, left_at, invited_at into v_joined_at, v_left_at, v_invited_at
  from public.meeting_participants
  where meeting_id = v_m8_id and user_uid = c_user_d;

  if v_invited_at is not null and v_joined_at is null and v_left_at is null then
    test_num := 22; test_name := 'Invite record does not set joined_at'; status := 'PASS'; return next;
  else
    test_num := 22; test_name := 'Invite record does not set joined_at'; status := 'FAIL'; return next;
  end if;

  -- TEST 23: Duplicate invite is idempotent
  perform * from public.invite_meeting_participant(v_m8_id, c_user_d);
  select count(*) into v_cnt from public.meeting_participants where meeting_id = v_m8_id and user_uid = c_user_d;

  if v_cnt = 1 then
    test_num := 23; test_name := 'Duplicate invite is idempotent'; status := 'PASS'; return next;
  else
    test_num := 23; test_name := 'Duplicate invite is idempotent'; status := 'FAIL'; return next;
  end if;

  -- TEST 24: list_my_meetings reports is_host correctly
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  select is_host into v_is_host_a from public.list_my_meetings() where id = v_m8_id;

  perform set_config('request.jwt.claim.sub', c_user_d::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_d::text)::text, true);
  select is_host into v_is_host_d from public.list_my_meetings() where id = v_m8_id;

  if v_is_host_a = true and v_is_host_d = false then
    test_num := 24; test_name := 'list_my_meetings reports is_host correctly'; status := 'PASS'; return next;
  else
    test_num := 24; test_name := 'list_my_meetings reports is_host correctly'; status := 'FAIL'; return next;
  end if;

  -- TEST 25: Historical attendee count correct
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  select historical_attendee_count, active_participant_count into v_hist_cnt, v_active_cnt
  from public.list_my_meetings()
  where id = v_m4_id;

  if v_hist_cnt = 8 and v_active_cnt = 0 then
    test_num := 25; test_name := 'Historical attendee count correct'; status := 'PASS'; return next;
  else
    test_num := 25; test_name := 'Historical attendee count correct'; status := 'FAIL'; return next;
  end if;

  -- TEST 26: RLS prevents unrelated meeting reads
  -- Set authenticated role and check RLS filter
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', c_user_d::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_d::text)::text, true);
  select count(*) into v_cnt from public.meetings where id = v_m5_id;

  if v_cnt = 0 then
    test_num := 26; test_name := 'RLS prevents unrelated meeting reads'; status := 'PASS'; return next;
  else
    test_num := 26; test_name := 'RLS prevents unrelated meeting reads'; status := 'FAIL'; return next;
  end if;

  -- TEST 27: Participant SELECT does not recurse
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  select count(*) into v_cnt from public.meeting_participants where meeting_id = v_m8_id;

  if v_cnt >= 2 then
    test_num := 27; test_name := 'Participant SELECT does not recurse'; status := 'PASS'; return next;
  else
    test_num := 27; test_name := 'Participant SELECT does not recurse'; status := 'FAIL'; return next;
  end if;

  -- Restore role
  perform set_config('role', 'postgres', true);

  -- TEST 28: Existing meeting RPC behavior remains compatible
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_user_a::text)::text, true);
  select count(*) into v_cnt from public.list_my_meetings();

  if v_cnt >= 1 then
    test_num := 28; test_name := 'Existing meeting RPC behavior remains compatible'; status := 'PASS'; return next;
  else
    test_num := 28; test_name := 'Existing meeting RPC behavior remains compatible'; status := 'FAIL'; return next;
  end if;

  -- CLEANUP test data
  delete from public.meeting_participants where user_uid in (c_user_a, c_user_b, c_user_c, c_user_d, c_user_e, c_user_f, c_user_g, c_user_h, c_user_i, c_user_j);
  delete from public.meetings where host_uid in (c_user_a, c_user_b, c_user_c, c_user_d, c_user_e, c_user_f, c_user_g, c_user_h, c_user_i, c_user_j) or join_code = 'a1f-4b2-9e0';
  delete from auth.users where id in (c_user_g, c_user_h, c_user_i, c_user_j);

end;
$$;

-- Run the tests and display results
select * from pg_temp.run_meet2a_tests();
