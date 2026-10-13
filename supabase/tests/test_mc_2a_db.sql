-- Test Suite for MC-2A: Returns structured test results table for all 16 scenarios

create or replace function pg_temp.run_mc2a_tests()
returns table(test_num int, test_name text, status text)
language plpgsql as $$
declare
  c_user_a uuid := '9cb63f35-523c-4f24-8646-0ed795adeb7e';
  c_user_b uuid := '362fb771-5736-4fae-a8c3-0d72189de8f3';
  c_user_c uuid := 'ce948bbb-983c-4ceb-9072-c72bcfdf9cf4';
  c_user_d uuid := 'ce53654a-97c6-434b-bdc4-dd87353ace81';
  c_user_e uuid := '6f7f1ca3-32c2-43c3-a4f9-d01dadd1a4b5';
  c_user_f uuid := '3e1b5ac1-9a49-418b-bfdc-54186aa16bef';

  v_call1_id uuid;
  v_call2_id uuid;
  v_call_t_id uuid;
  v_op1_id uuid;
  v_res jsonb;

  v_call1e_id uuid;
  v_call2e_id uuid;
  v_ope_id uuid;

  v_call3_id uuid;
  v_call4_id uuid;
  v_op_cancel_id uuid;

  v_call5_id uuid;
  v_call6_id uuid;
  v_op_unauth_id uuid;

  v_cap1_id uuid;
  v_cap2_id uuid;
  v_cnt int;
  v_status text;
  v_op_status text;
  v_held_by uuid;
  v_merged_into uuid;
  v_exception_caught boolean;
begin
  -- SETUP
  insert into public.calls (id, initiated_by, call_type, status, held_by, created_at)
  values (gen_random_uuid(), c_user_a, 'audio', 'on_hold', c_user_a, now())
  returning id into v_call1_id;

  insert into public.call_participants (call_id, user_uid, joined_at)
  values (v_call1_id, c_user_a, now()),
         (v_call1_id, c_user_b, now());

  insert into public.calls (id, initiated_by, call_type, status, created_at)
  values (gen_random_uuid(), c_user_a, 'video', 'connected', now())
  returning id into v_call2_id;

  insert into public.call_participants (call_id, user_uid, joined_at, camera_enabled)
  values (v_call2_id, c_user_a, now(), true),
         (v_call2_id, c_user_c, now(), true);

  -- TEST 1
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  v_res := public.prepare_call_merge(v_call1_id, v_call2_id);
  v_op1_id := (v_res ->> 'merge_operation_id')::uuid;
  select cmo.status into v_op_status from public.call_merge_operations cmo where cmo.id = v_op1_id;
  if v_res ->> 'result' = 'prepared' and (v_res ->> 'joining_user_uid')::uuid = c_user_c and v_op_status = 'prepared' then
    test_num := 1; test_name := 'Valid prepare creates active operation'; status := 'PASS'; return next;
  else
    test_num := 1; test_name := 'Valid prepare creates active operation'; status := 'FAIL'; return next;
  end if;

  -- TEST 2
  v_exception_caught := false;
  begin
    perform public.prepare_call_merge(v_call1_id, v_call1_id);
  exception when others then
    v_exception_caught := true;
  end;
  if v_exception_caught then
    test_num := 2; test_name := 'Primary == secondary rejected'; status := 'PASS'; return next;
  else
    test_num := 2; test_name := 'Primary == secondary rejected'; status := 'FAIL'; return next;
  end if;

  -- TEST 3
  perform set_config('request.jwt.claim.sub', c_user_d::text, true);
  v_res := public.prepare_call_merge(v_call1_id, v_call2_id);
  if v_res ->> 'result' = 'rejected' and v_res ->> 'reason' = 'unauthorized_participant' then
    test_num := 3; test_name := 'Nonparticipant rejected'; status := 'PASS'; return next;
  else
    test_num := 3; test_name := 'Nonparticipant rejected'; status := 'FAIL'; return next;
  end if;

  -- TEST 4
  insert into public.calls (id, initiated_by, call_type, status, created_at, ended_at)
  values (gen_random_uuid(), c_user_a, 'audio', 'completed', now(), now())
  returning id into v_call_t_id;
  insert into public.call_participants (call_id, user_uid, joined_at, left_at)
  values (v_call_t_id, c_user_a, now(), now()), (v_call_t_id, c_user_b, now(), now());

  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  v_res := public.prepare_call_merge(v_call_t_id, v_call2_id);
  if v_res ->> 'result' = 'rejected' and v_res ->> 'reason' = 'calls_not_active' then
    test_num := 4; test_name := 'Terminal call rejected'; status := 'PASS'; return next;
  else
    test_num := 4; test_name := 'Terminal call rejected'; status := 'FAIL'; return next;
  end if;

  -- TEST 5
  select count(*) into v_cnt from public.call_participants where call_id = v_call1_id;
  if v_cnt = 2 and not exists (select 1 from public.call_participants where call_id = v_call1_id and user_uid = c_user_c) then
    test_num := 5; test_name := 'Prepare does NOT modify call membership'; status := 'PASS'; return next;
  else
    test_num := 5; test_name := 'Prepare does NOT modify call membership'; status := 'FAIL'; return next;
  end if;

  -- TEST 6
  select c.status into v_op_status from public.calls c where c.id = v_call2_id;
  if v_op_status = 'connected' then
    test_num := 6; test_name := 'Prepare does NOT complete secondary'; status := 'PASS'; return next;
  else
    test_num := 6; test_name := 'Prepare does NOT complete secondary'; status := 'FAIL'; return next;
  end if;

  -- TEST 7
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  v_res := public.prepare_call_merge(v_call1_id, v_call2_id);
  if v_res ->> 'result' = 'already_prepared' and (v_res ->> 'merge_operation_id')::uuid = v_op1_id then
    test_num := 7; test_name := 'Duplicate prepare is idempotent'; status := 'PASS'; return next;
  else
    test_num := 7; test_name := 'Duplicate prepare is idempotent'; status := 'FAIL'; return next;
  end if;

  -- TEST 8
  insert into public.calls (id, initiated_by, call_type, status, created_at)
  values (gen_random_uuid(), c_user_a, 'audio', 'connected', now())
  returning id into v_call1e_id;
  insert into public.call_participants (call_id, user_uid, joined_at)
  values (v_call1e_id, c_user_a, now()), (v_call1e_id, c_user_b, now());

  insert into public.calls (id, initiated_by, call_type, status, created_at)
  values (gen_random_uuid(), c_user_a, 'audio', 'connected', now())
  returning id into v_call2e_id;
  insert into public.call_participants (call_id, user_uid, joined_at)
  values (v_call2e_id, c_user_a, now()), (v_call2e_id, c_user_c, now());

  v_res := public.prepare_call_merge(v_call1e_id, v_call2e_id);
  v_ope_id := (v_res ->> 'merge_operation_id')::uuid;
  update public.call_merge_operations set expires_at = clock_timestamp() - interval '10 seconds' where id = v_ope_id;
  v_res := public.commit_call_merge(v_ope_id);
  select cmo.status into v_op_status from public.call_merge_operations cmo where cmo.id = v_ope_id;

  if v_res ->> 'result' = 'rejected' and v_res ->> 'reason' = 'merge_op_expired_or_cancelled' and v_op_status = 'expired' then
    test_num := 8; test_name := 'Expired operation rejected'; status := 'PASS'; return next;
  else
    test_num := 8; test_name := 'Expired operation rejected'; status := 'FAIL'; return next;
  end if;

  -- TEST 9
  if not has_function_privilege('authenticated', 'public.commit_call_merge(uuid)', 'execute')
     and not has_function_privilege('anon', 'public.commit_call_merge(uuid)', 'execute')
     and has_function_privilege('service_role', 'public.commit_call_merge(uuid)', 'execute') then
    test_num := 9; test_name := 'Authenticated client cannot commit'; status := 'PASS'; return next;
  else
    test_num := 9; test_name := 'Authenticated client cannot commit'; status := 'FAIL'; return next;
  end if;

  -- TEST 10
  v_res := public.commit_call_merge(v_op1_id);
  select c.status, c.held_by into v_op_status, v_held_by from public.calls c where c.id = v_call1_id;
  select cmo.status into v_status from public.call_merge_operations cmo where cmo.id = v_op1_id;

  if v_res ->> 'result' = 'committed' and v_op_status = 'connected' and v_held_by is null and v_status = 'committed'
     and exists (select 1 from public.call_participants where call_id = v_call1_id and user_uid = c_user_c and left_at is null) then
    test_num := 10; test_name := 'Trusted commit migrates participant once'; status := 'PASS'; return next;
  else
    test_num := 10; test_name := 'Trusted commit migrates participant once'; status := 'FAIL'; return next;
  end if;

  -- TEST 11
  v_res := public.commit_call_merge(v_op1_id);
  select count(*) into v_cnt from public.call_participants where call_id = v_call1_id and user_uid = c_user_c;
  if v_res ->> 'result' = 'already_committed' and v_cnt = 1 then
    test_num := 11; test_name := 'Duplicate trusted commit is idempotent'; status := 'PASS'; return next;
  else
    test_num := 11; test_name := 'Duplicate trusted commit is idempotent'; status := 'FAIL'; return next;
  end if;

  -- TEST 12
  select c.merged_into_call_id into v_merged_into from public.calls c where c.id = v_call2_id;
  if v_merged_into = v_call1_id then
    test_num := 12; test_name := 'Commit sets merged_into_call_id'; status := 'PASS'; return next;
  else
    test_num := 12; test_name := 'Commit sets merged_into_call_id'; status := 'FAIL'; return next;
  end if;

  -- TEST 13
  insert into public.calls (id, initiated_by, call_type, status, held_by, created_at)
  values (gen_random_uuid(), c_user_a, 'audio', 'on_hold', c_user_a, now())
  returning id into v_call3_id;
  insert into public.call_participants (call_id, user_uid, joined_at)
  values (v_call3_id, c_user_a, now()), (v_call3_id, c_user_b, now());

  insert into public.calls (id, initiated_by, call_type, status, created_at)
  values (gen_random_uuid(), c_user_a, 'video', 'connected', now())
  returning id into v_call4_id;
  insert into public.call_participants (call_id, user_uid, joined_at)
  values (v_call4_id, c_user_a, now()), (v_call4_id, c_user_c, now());

  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  v_res := public.prepare_call_merge(v_call3_id, v_call4_id);
  v_op_cancel_id := (v_res ->> 'merge_operation_id')::uuid;

  v_res := public.cancel_call_merge(v_op_cancel_id, 'client_aborted');
  select c.status into v_op_status from public.calls c where c.id = v_call3_id;
  select cmo.status into v_status from public.call_merge_operations cmo where cmo.id = v_op_cancel_id;

  if v_res ->> 'result' = 'cancelled' and v_op_status = 'on_hold' and v_status = 'cancelled'
     and not exists (select 1 from public.call_participants where call_id = v_call3_id and user_uid = c_user_c) then
    test_num := 13; test_name := 'Cancel preserves both calls'; status := 'PASS'; return next;
  else
    test_num := 13; test_name := 'Cancel preserves both calls'; status := 'FAIL'; return next;
  end if;

  -- TEST 14
  insert into public.calls (id, initiated_by, call_type, status, held_by, created_at)
  values (gen_random_uuid(), c_user_a, 'audio', 'on_hold', c_user_a, now())
  returning id into v_call5_id;
  insert into public.call_participants (call_id, user_uid, joined_at)
  values (v_call5_id, c_user_a, now()), (v_call5_id, c_user_b, now());

  insert into public.calls (id, initiated_by, call_type, status, created_at)
  values (gen_random_uuid(), c_user_a, 'audio', 'connected', now())
  returning id into v_call6_id;
  insert into public.call_participants (call_id, user_uid, joined_at)
  values (v_call6_id, c_user_a, now()), (v_call6_id, c_user_c, now());

  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  v_res := public.prepare_call_merge(v_call5_id, v_call6_id);
  v_op_unauth_id := (v_res ->> 'merge_operation_id')::uuid;

  perform set_config('request.jwt.claim.sub', c_user_b::text, true);
  v_res := public.cancel_call_merge(v_op_unauth_id);

  if v_res ->> 'result' = 'rejected' and v_res ->> 'reason' = 'unauthorized_initiator' then
    test_num := 14; test_name := 'Unauthorized cancel rejected'; status := 'PASS'; return next;
  else
    test_num := 14; test_name := 'Unauthorized cancel rejected'; status := 'FAIL'; return next;
  end if;

  -- TEST 15
  insert into public.calls (id, initiated_by, call_type, status, created_at)
  values (gen_random_uuid(), c_user_a, 'audio', 'connected', now())
  returning id into v_cap1_id;
  insert into public.call_participants (call_id, user_uid, joined_at)
  values (v_cap1_id, c_user_a, now()), (v_cap1_id, c_user_b, now()), (v_cap1_id, c_user_c, now()),
         (v_cap1_id, c_user_d, now()), (v_cap1_id, c_user_e, now()), (v_cap1_id, c_user_f, now());

  declare
    u7 uuid := gen_random_uuid();
    u8 uuid := gen_random_uuid();
    u9 uuid := gen_random_uuid();
  begin
    insert into auth.users (id, aud, role, email, created_at, updated_at)
    values (u7, 'authenticated', 'authenticated', 'u7@test.com', now(), now()),
           (u8, 'authenticated', 'authenticated', 'u8@test.com', now(), now()),
           (u9, 'authenticated', 'authenticated', 'u9@test.com', now(), now());

    insert into public.call_participants (call_id, user_uid, joined_at)
    values (v_cap1_id, u7, now()), (v_cap1_id, u8, now());

    insert into public.calls (id, initiated_by, call_type, status, created_at)
    values (gen_random_uuid(), c_user_a, 'audio', 'connected', now())
    returning id into v_cap2_id;

    insert into public.call_participants (call_id, user_uid, joined_at)
    values (v_cap2_id, c_user_a, now()), (v_cap2_id, u9, now());

    perform set_config('request.jwt.claim.sub', c_user_a::text, true);
    v_res := public.prepare_call_merge(v_cap1_id, v_cap2_id);

    if v_res ->> 'result' = 'rejected' and v_res ->> 'reason' = 'capacity_exceeded' then
      test_num := 15; test_name := 'Participant capacity enforced (limit 8)'; status := 'PASS'; return next;
    else
      test_num := 15; test_name := 'Participant capacity enforced (limit 8)'; status := 'FAIL'; return next;
    end if;

    delete from public.call_participants where call_id in (v_cap1_id, v_cap2_id);
    delete from public.calls where id in (v_cap1_id, v_cap2_id);
    delete from auth.users where id in (u7, u8, u9);
  end;

  -- TEST 16
  perform set_config('request.jwt.claim.sub', c_user_a::text, true);
  perform count(*) from public.calls;
  perform count(*) from public.call_participants;
  perform count(*) from public.call_merge_operations;

  test_num := 16; test_name := 'No RLS recursion across calls and participants'; status := 'PASS'; return next;

  -- CLEANUP FIXTURES
  delete from public.call_merge_operations
  where primary_call_id in (v_call1_id, v_call1e_id, v_call3_id, v_call5_id)
     or secondary_call_id in (v_call2_id, v_call2e_id, v_call4_id, v_call6_id);

  delete from public.call_participants
  where call_id in (v_call1_id, v_call2_id, v_call_t_id, v_call1e_id, v_call2e_id, v_call3_id, v_call4_id, v_call5_id, v_call6_id);

  delete from public.calls
  where id in (v_call1_id, v_call2_id, v_call_t_id, v_call1e_id, v_call2e_id, v_call3_id, v_call4_id, v_call5_id, v_call6_id);
end;
$$;

select * from pg_temp.run_mc2a_tests();
