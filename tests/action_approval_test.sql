\set ON_ERROR_STOP on
begin;
do $$ begin
    begin
        perform beacon_private.check_action('{"vad_shared_station_state_v14":{"2":{}}}', '2', 'explore');
        raise exception 'room with missing unlocked field accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform beacon_private.check_action('{"vad_shared_station_state_v14":{"7b":{"unlocked":true}}}', '7b', 'explore');
        raise exception '7b without visibility accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform beacon_private.check_action('{"vad_shared_station_state_v14":{"2":{"unlocked":true}}}', '2', 'search');
        raise exception 'room with missing explored field accepted';
    exception when invalid_parameter_value then null; end;
end $$;
insert into auth.users(id) values ('99999999-9999-4999-8999-999999999999');
insert into beacon_private.sessions(owner_id,join_code,shared)
values ('99999999-9999-4999-8999-999999999999', repeat('e',64),
    jsonb_build_object('vad_shared_station_state_v14',beacon_private.initial_rooms()));
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
begin
    begin
        perform public.beacon_update(repeat('e',64),1,'vad_shared_station_state_v14','{"2":{"explored":true}}',0);
        raise exception 'player bypassed approval';
    exception when insufficient_privilege then null; end;
    begin
        perform public.beacon_request_action(repeat('e',64),1,'2','search',gen_random_uuid(),0);
        raise exception 'search before explore accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.beacon_request_action(repeat('e',64),1,'5','explore',gen_random_uuid(),0);
        raise exception 'locked room request accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.beacon_request_action(repeat('e',64),2,'2','explore',gen_random_uuid(),0);
        raise exception 'disabled group accepted';
    exception when insufficient_privilege then null; end;
end $$;
select public.beacon_request_action(repeat('e',64),1,'2','explore','11111111-1111-4111-8111-111111111111',0);
select public.beacon_request_action(repeat('e',64),1,'2','explore','11111111-1111-4111-8111-111111111111',0);
do $$ declare d jsonb;
begin
    d := public.beacon_read_session(repeat('e',64),1);
    if jsonb_array_length(d -> 'action_requests') <> 1 or d #>> '{shared,vad_shared_station_state_v14,2,explored}' <> 'false' then
        raise exception 'request unexpectedly applied or duplicated: %', d;
    end if;
    begin
        perform public.beacon_decide_action(repeat('e',64),'11111111-1111-4111-8111-111111111111',true,0);
        raise exception 'player approved';
    exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '99999999-9999-4999-8999-999999999999', true);
set local role authenticated;
select public.beacon_decide_action(repeat('e',64),'11111111-1111-4111-8111-111111111111',true,0);
select public.beacon_decide_action(repeat('e',64),'11111111-1111-4111-8111-111111111111',true,0);
do $$ declare d jsonb;
begin
    d := public.beacon_read_session(repeat('e',64),null);
    if d #>> '{shared,vad_shared_station_state_v14,2,explored}' <> 'true'
        or d #>> '{private,vad_session_log_v1,0,group}' <> '1'
        or jsonb_array_length(d #> '{private,vad_session_log_v1}') <> 1 then
        raise exception 'approval did not apply once: %', d;
    end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
select public.beacon_request_action(repeat('e',64),1,'2','search','22222222-2222-4222-8222-222222222222',0);
select public.beacon_request_action(repeat('e',64),1,'2','log','33333333-3333-4333-8333-333333333333',0);
reset role;
select set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',true);
set local role authenticated;
select public.beacon_decide_action(repeat('e',64),'22222222-2222-4222-8222-222222222222',false,0);
select public.beacon_decide_action(repeat('e',64),'33333333-3333-4333-8333-333333333333',true,0);
do $$ declare d jsonb;
begin
    d := public.beacon_read_session(repeat('e',64),null);
    if d #>> '{shared,vad_shared_station_state_v14,2,searched}' <> 'false'
        or d #>> '{shared,vad_shared_station_state_v14,2,logUnlocked}' <> 'true' then
        raise exception 'incorrect reject/approve result: %', d;
    end if;
end $$;
select public.beacon_reset(repeat('e',64));
do $$ begin
    if jsonb_array_length(public.beacon_read_session(repeat('e',64),null) -> 'action_requests') <> 0 then
        raise exception 'reset retained requests';
    end if;
    begin
        perform public.beacon_request_action(repeat('e',64),1,'2','explore',gen_random_uuid(),0);
        raise exception 'stale request accepted';
    exception when serialization_failure then null; end;
end $$;
rollback;
