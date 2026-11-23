\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values ('11111111-1111-4111-8111-111111111112');
insert into beacon_private.sessions(owner_id, join_code, shared)
values ('11111111-1111-4111-8111-111111111112', repeat('b', 64),
    jsonb_build_object('vad_shared_station_state_v14', beacon_private.initial_rooms()));
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111112', true);
set local role authenticated;
select public.beacon_publish_ship(repeat('b', 64), '{"name":"Test Ship","rooms":[]}', 0);
select public.beacon_set_group(repeat('b', 64), 2, true);
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select public.beacon_request_ship_item(repeat('b', 64), 2, 'up_armor', 2, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 0);
select public.beacon_request_ship_item(repeat('b', 64), 2, 'up_armor', 2, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 0);
do $$
declare data jsonb;
begin
    data := public.beacon_read_session(repeat('b', 64), 1);
    if data #>> '{ship,name}' <> 'Test Ship' or jsonb_array_length(data -> 'ship_requests') <> 1
        or data #>> '{ship_requests,0,group}' <> '2' or data #>> '{ship_requests,0,status}' <> 'pending' then
        raise exception 'request not shared: %', data;
    end if;
    begin
        perform public.beacon_request_ship_item(repeat('b', 64), 2, 'gear_vaccsuit', 1, gen_random_uuid(), 0);
        raise exception 'crew gear request accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.beacon_request_ship_item(repeat('b', 64), 3, 'up_armor', 1, gen_random_uuid(), 0);
        raise exception 'disabled group request accepted';
    exception when insufficient_privilege then null; end;
    begin
        perform public.beacon_request_ship_item(repeat('b', 64), 2, 'up_armor', 21, gen_random_uuid(), 0);
        raise exception 'invalid quantity accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.beacon_request_ship_item(repeat('b', 64), 2, 'up_jump', 1, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 0);
        raise exception 'changed duplicate accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.beacon_publish_ship(repeat('b', 64), '{"name":"Forged","rooms":[]}', 0);
        raise exception 'player published ship';
    exception when insufficient_privilege then null; end;
    begin
        perform public.beacon_decide_ship_request(repeat('b', 64), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'approved', 0);
        raise exception 'player approved request';
    exception when insufficient_privilege then null; end;
    begin
        perform * from beacon_private.ship_requests;
        raise exception 'player accessed private requests table';
    exception when insufficient_privilege then null; end;
end $$;
select public.beacon_request_ship_item(repeat('b', 64), 1, 'dry_hull_10', 1, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 0);
reset role;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111112', true);
set local role authenticated;
select public.beacon_decide_ship_request(repeat('b', 64), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'approved', 0);
select public.beacon_decide_ship_request(repeat('b', 64), 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'rejected', 0);
do $$
declare data jsonb;
begin
    data := public.beacon_read_session(repeat('b', 64), null);
    if not exists (select 1 from jsonb_array_elements(data -> 'ship_requests') r
            where r ->> 'id' = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and r ->> 'status' = 'approved')
        or not exists (select 1 from jsonb_array_elements(data -> 'ship_requests') r
            where r ->> 'id' = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and r ->> 'status' = 'rejected')
        or data #>> '{ship,name}' <> 'Test Ship' then
        raise exception 'approval should not change ship: %', data;
    end if;
    begin
        perform public.beacon_decide_ship_request(repeat('b', 64), 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'rejected', 0);
        raise exception 'already decided request was changed';
    exception when invalid_parameter_value then null; end;
end $$;
select public.beacon_reset(repeat('b', 64));
do $$
declare data jsonb;
begin
    data := public.beacon_read_session(repeat('b', 64), null);
    if data #>> '{ship,name}' <> 'Test Ship' or jsonb_array_length(data -> 'ship_requests') <> 2 then
        raise exception 'reset lost ship or requests: %', data;
    end if;
    begin
        perform public.beacon_request_ship_item(repeat('b', 64), 1, 'up_armor', 1, gen_random_uuid(), 0);
        raise exception 'stale request accepted';
    exception when serialization_failure then null; end;
end $$;
select public.beacon_clear_decided_ship_requests(repeat('b', 64), 1);
do $$ begin
    if jsonb_array_length(public.beacon_read_session(repeat('b', 64), null) -> 'ship_requests') <> 0 then
        raise exception 'decided requests not cleared';
    end if;
end $$;
rollback;
