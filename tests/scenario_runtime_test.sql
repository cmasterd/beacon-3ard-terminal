\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values ('99999999-9999-4999-8999-999999999971'), ('99999999-9999-4999-8999-999999999972');
insert into beacon_private.games(id,owner_id,title,engine)
values ('11111111-1111-4111-8111-111111111111','99999999-9999-4999-8999-999999999971','Ghost Ship','scenario');
insert into beacon_private.game_versions(id,game_id,version,definition)
values ('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111',1,
    '{"catalog":{"title":"Ghost Ship"},"definition":{"format":"vad-scenario","version":1,"nodes":[
      {"id":"bridge","name":"Secret bridge","level":"01","description":"Hidden sector description","status":"ONLINE",
       "isLocked":false,"keypadCode":"4821","wardenNotes":"private note","items":[{"id":"key","name":"Hidden key","isHeavy":false,"secret":"item secret"}],
       "logs":[{"id":"log","title":"Hidden log","author":"Crew","body":"Hidden log body","stress":1,"secret":"log secret"}]},
      {"id":"locked","name":"Locked room","level":"02","description":"Other secret","status":"LOCKED",
       "isLocked":true,"keypadCode":"9999","items":[],"logs":[]}
    ]}}');
insert into beacon_private.game_sessions(id,owner_id,game_id,name,version_id)
values ('33333333-3333-4333-8333-333333333333','99999999-9999-4999-8999-999999999971',
    '11111111-1111-4111-8111-111111111111','Friday','22222222-2222-4222-8222-222222222222'),
    ('44444444-4444-4444-8444-444444444444','99999999-9999-4999-8999-999999999971',
    '11111111-1111-4111-8111-111111111111','Saturday','22222222-2222-4222-8222-222222222222');
insert into beacon_private.game_session_groups(session_id,group_number,enabled,location_id)
values ('33333333-3333-4333-8333-333333333333',1,true,'bridge'),
       ('33333333-3333-4333-8333-333333333333',2,false,null),
       ('44444444-4444-4444-8444-444444444444',1,true,'bridge');
select set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999971',true);
set local role authenticated;
select set_config('test.code', public.scenario_activate_session('33333333-3333-4333-8333-333333333333')->>'player_code', true);
select set_config('test.code2', public.scenario_activate_session('44444444-4444-4444-8444-444444444444')->>'player_code', true);
do $$ begin
    if current_setting('test.code') = current_setting('test.code2')
        or public.scenario_activate_session('33333333-3333-4333-8333-333333333333')->>'player_code' <> current_setting('test.code') then
        raise exception 'session capability is not unique or activation not idempotent';
    end if;
end $$;
reset role;
set local role anon;
do $$ declare v jsonb; begin
    v := public.scenario_player_view(current_setting('test.code'),1);
    if v::text like '%Secret bridge%' or v::text like '%Hidden%' or v::text like '%4821%'
        or v::text like '%private note%' or jsonb_array_length(v->'rooms') <> 2 then
        raise exception 'initial view leaks protected content: %', v;
    end if;
    begin
        perform public.scenario_player_view('invalid',1);
        raise exception 'invalid capability accepted';
    exception when insufficient_privilege then null; end;
    begin
        perform public.scenario_player_view(current_setting('test.code'),2);
        raise exception 'disabled group accepted';
    exception when insufficient_privilege then null; end;
    begin
        perform public.scenario_request_action(current_setting('test.code'),1,'bridge','search',gen_random_uuid());
        raise exception 'search before explore accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.scenario_decide_action('33333333-3333-4333-8333-333333333333',gen_random_uuid(),true);
        raise exception 'anonymous decision accepted';
    exception when insufficient_privilege then null; end;
end $$;
select public.scenario_request_action(current_setting('test.code'),1,'bridge','explore','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select public.scenario_request_action(current_setting('test.code'),1,'bridge','explore','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
do $$ begin
    begin
        perform public.scenario_request_action(current_setting('test.code'),1,'bridge','explore',gen_random_uuid());
        raise exception 'duplicate pending request accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.scenario_request_action(current_setting('test.code'),1,'bridge','log','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
        raise exception 'changed duplicate request accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.scenario_request_action(current_setting('test.code'),2,'bridge','explore',gen_random_uuid());
        raise exception 'disabled group requested action';
    exception when insufficient_privilege then null; end;
    begin
        perform * from beacon_private.scenario_progress;
        raise exception 'player accessed private progress directly';
    exception when insufficient_privilege then null; end;
    if public.scenario_player_view(current_setting('test.code'),1)::text like '%Hidden sector%' then
        raise exception 'pending action revealed description';
    end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999972',true);
set local role authenticated;
do $$ begin
    begin
        perform public.scenario_decide_action('33333333-3333-4333-8333-333333333333','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
        raise exception 'another Warden approved request';
    exception when insufficient_privilege then null; end;
    begin
        perform public.scenario_activate_session('33333333-3333-4333-8333-333333333333');
        raise exception 'another Warden obtained player credential';
    exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999971',true);
set local role authenticated;
select public.scenario_decide_action('33333333-3333-4333-8333-333333333333','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
select public.scenario_decide_action('33333333-3333-4333-8333-333333333333','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
reset role;
set local role anon;
do $$ declare v text; begin
    v := public.scenario_player_view(current_setting('test.code'),1)::text;
    if v not like '%Hidden sector description%' or v like '%Hidden key%' or v like '%Hidden log body%'
        or v like '%4821%' or v like '%private note%' then raise exception 'explore projection incorrect: %', v; end if;
    if public.scenario_player_view(current_setting('test.code2'),1)::text like '%Hidden sector description%' then
        raise exception 'progress leaked between sessions';
    end if;
end $$;
select public.scenario_request_action(current_setting('test.code'),1,'bridge','search','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
select public.scenario_request_action(current_setting('test.code'),1,'bridge','log','cccccccc-cccc-4ccc-8ccc-cccccccccccc');
reset role;
set local role authenticated;
select public.scenario_decide_action('33333333-3333-4333-8333-333333333333','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',false);
select public.scenario_decide_action('33333333-3333-4333-8333-333333333333','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true);
do $$ begin
    begin
        perform public.scenario_decide_action('33333333-3333-4333-8333-333333333333','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
        raise exception 'conflicting decision accepted';
    exception when invalid_parameter_value then null; end;
end $$;
reset role;
set local role anon;
do $$ declare v text; begin
    v := public.scenario_player_view(current_setting('test.code'),1)::text;
    if v not like '%Hidden log body%' or v like '%Hidden key%' or v like '%log secret%' or v like '%4821%' then
        raise exception 'search rejection or log projection incorrect: %', v;
    end if;
end $$;
select public.scenario_request_action(current_setting('test.code'),1,'bridge','search','dddddddd-dddd-4ddd-8ddd-dddddddddddd');
reset role;
set local role authenticated;
select public.scenario_decide_action('33333333-3333-4333-8333-333333333333','dddddddd-dddd-4ddd-8ddd-dddddddddddd',true);
reset role;
set local role anon;
do $$ declare v text; begin
    v := public.scenario_player_view(current_setting('test.code'),1)::text;
    if v not like '%Hidden key%' or v like '%item secret%' or v like '%9999%' then
        raise exception 'search projection incorrect: %', v;
    end if;
end $$;
select public.scenario_move(current_setting('test.code'),1,'locked');
do $$ begin
    begin
        perform public.scenario_request_action(current_setting('test.code'),1,'bridge','explore',gen_random_uuid());
        raise exception 'action requested away from current room';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.scenario_request_action(current_setting('test.code'),1,'locked','explore',gen_random_uuid());
        raise exception 'locked room explored';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.scenario_move(current_setting('test.code'),1,'missing');
        raise exception 'movement to nonexistent room accepted';
    exception when invalid_parameter_value then null; end;
end $$;
reset role;
-- Activation rejects malformed values that could otherwise smuggle objects into a projection.
update beacon_private.game_versions set definition = jsonb_set(definition,'{definition,nodes,0,name}','{"keypadCode":"4821"}');
select set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999971',true);
set local role authenticated;
do $$ begin
    begin
        perform public.scenario_activate_session('33333333-3333-4333-8333-333333333333');
        raise exception 'malformed projected field accepted';
    exception when invalid_parameter_value then null; end;
end $$;
rollback;
