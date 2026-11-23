\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values ('99999999-9999-4999-8999-999999999981'), ('99999999-9999-4999-8999-999999999982');
set local role anon;
do $$ begin
    begin
        perform public.game_list_my_prepared_sessions();
        raise exception 'anonymous user listed sessions';
    exception when insufficient_privilege then null; end;
    begin
        perform public.game_prepare_session(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'Intruder');
        raise exception 'anonymous user prepared session';
    exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '99999999-9999-4999-8999-999999999981', true);
set local role authenticated;
do $$
declare
    game_id constant uuid := '11111111-1111-4111-8111-111111111111';
    version_id constant uuid := '22222222-2222-4222-8222-222222222222';
    session_a constant uuid := '33333333-3333-4333-8333-333333333333';
    session_b constant uuid := '44444444-4444-4444-8444-444444444444';
    package jsonb := '{"catalog":{"title":"Ghost Ship","description":""},"definition":{"format":"vad-scenario","version":1,"initialState":{"partyNodeId":"bridge","hunterNodeId":"hold","stress":2,"worldFlags":{},"clocks":[],"inventory":[{"id":"key","name":"Secret key"}]},"nodes":[{"id":"bridge","keypadCode":"4821"},{"id":"hold"}]}}';
begin
    perform public.game_save_draft(game_id, version_id, 0, package);
    perform public.game_prepare_session(session_a, game_id, version_id, 'Friday');
    perform public.game_prepare_session(session_a, game_id, version_id, 'Friday');
    perform public.game_prepare_session(session_b, game_id, version_id, 'Saturday');
    if jsonb_array_length(public.game_list_my_prepared_sessions()) <> 2
        or public.game_list_my_prepared_sessions()::text like '%4821%'
        or public.game_list_my_prepared_sessions()::text like '%Secret key%' then
        raise exception 'session listing is incorrect or exposed secrets';
    end if;
    begin
        perform public.game_prepare_session(session_a, game_id, version_id, 'Changed');
        raise exception 'changed retry accepted';
    exception when invalid_parameter_value then null; end;
    package := jsonb_set(package, '{definition,initialState,partyNodeId}', '"missing"');
    perform public.game_save_draft(game_id, '55555555-5555-4555-8555-555555555555', 1, package);
    begin
        perform public.game_prepare_session(gen_random_uuid(), game_id, '55555555-5555-4555-8555-555555555555', 'Bad');
        raise exception 'missing start room accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.game_prepare_session(gen_random_uuid(), game_id, gen_random_uuid(), 'Bad version');
        raise exception 'unknown version accepted';
    exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
    if (select count(*) from beacon_private.game_sessions where name in ('Friday','Saturday')) <> 2
        or (select count(*) from beacon_private.game_session_groups where session_id in
            ('33333333-3333-4333-8333-333333333333','44444444-4444-4444-8444-444444444444')) <> 8
        or (select location_id from beacon_private.game_session_groups where
            session_id = '33333333-3333-4333-8333-333333333333' and group_number = 1) <> 'bridge'
        or (select inventory #>> '{0,name}' from beacon_private.game_session_groups where
            session_id = '33333333-3333-4333-8333-333333333333' and group_number = 1) <> 'Secret key'
        or (select world_state ->> 'hunterNodeId' from beacon_private.game_session_state where
            session_id = '33333333-3333-4333-8333-333333333333') <> 'hold' then
        raise exception 'session initialization failed';
    end if;
    update beacon_private.game_session_state set world_state = jsonb_set(world_state, '{stress}', '8')
        where session_id = '33333333-3333-4333-8333-333333333333';
    if (select world_state ->> 'stress' from beacon_private.game_session_state where
        session_id = '44444444-4444-4444-8444-444444444444') <> '2'
        or (select version_id from beacon_private.game_sessions where id =
            '33333333-3333-4333-8333-333333333333') <> '22222222-2222-4222-8222-222222222222'::uuid then
        raise exception 'sessions share state or version changed';
    end if;
end $$;
select set_config('request.jwt.claim.sub', '99999999-9999-4999-8999-999999999982', true);
set local role authenticated;
do $$ begin
    if jsonb_array_length(public.game_list_my_prepared_sessions()) <> 0 then
        raise exception 'another Warden can list sessions';
    end if;
    begin
        perform public.game_prepare_session(gen_random_uuid(), '11111111-1111-4111-8111-111111111111',
            '22222222-2222-4222-8222-222222222222', 'Intruder');
        raise exception 'another Warden used private draft';
    exception when insufficient_privilege then null; end;
    begin
        perform * from beacon_private.game_session_state;
        raise exception 'another Warden read private state';
    exception when insufficient_privilege then null; end;
end $$;
rollback;
