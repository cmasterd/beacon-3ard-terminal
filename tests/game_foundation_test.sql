\set ON_ERROR_STOP on
begin;

-- A migrated session retains the same credential, state and ship requests.
do $$
declare session_row beacon_private.sessions%rowtype;
begin
    select * into strict session_row from beacon_private.sessions
        where owner_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    if session_row.join_code <> repeat('a', 64) or session_row.player_code <> 'ABCDE'
        or session_row.shared #>> '{vad_shared_station_state_v14,2,explored}' <> 'true'
        or session_row.private_data ->> 'vad_warden_notes_v1' <> 'Private notes'
        or session_row.groups ->> '2' <> 'true' or session_row.presence #>> '{2,room}' <> '3'
        or session_row.ship_data ->> 'name' <> 'Existing ship' or session_row.reset_epoch <> 7
        or (select count(*) from beacon_private.ship_requests where owner_id = session_row.owner_id) <> 1
        or (select count(*) from beacon_private.game_sessions where legacy_owner_id = session_row.owner_id) <> 1 then
        raise exception 'legacy session was altered or not mapped';
    end if;
end $$;

insert into auth.users(id) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
insert into beacon_private.sessions(owner_id, join_code)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', repeat('b', 64));
do $$ begin
    if (select count(*) from beacon_private.game_sessions
        where legacy_owner_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') <> 1 then
        raise exception 'new legacy session was not mapped';
    end if;
end $$;

-- Prototype records exercise multiple named sessions without exposing a
-- session creation API before the scenario engine and permissions exist.
insert into beacon_private.games(id, owner_id, title, description, engine, published)
values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'Ghost Ship', 'An abandoned vessel', 'scenario', true),
    ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'Unpublished secret', '', 'scenario', false);
insert into beacon_private.game_versions(id, game_id, version, definition)
values ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    1, '{"secret_code":"4821","hidden_log":"secret"}');
insert into beacon_private.game_sessions(owner_id, game_id, name, version_id)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'Friday crew', 'ffffffff-ffff-4fff-8fff-ffffffffffff'),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'Saturday crew', 'ffffffff-ffff-4fff-8fff-ffffffffffff');
insert into beacon_private.game_session_state(session_id, world_state, ship_data)
select id, '{"clock":2}', '{"name":"Friday ship"}'
from beacon_private.game_sessions where name = 'Friday crew';
insert into beacon_private.game_session_state(session_id, world_state)
select id, '{"clock":5}' from beacon_private.game_sessions where name = 'Saturday crew';
insert into beacon_private.game_session_groups(session_id, group_number, enabled, inventory)
select id, 1, true, '["Friday key"]'
from beacon_private.game_sessions where name = 'Friday crew';
insert into beacon_private.game_session_groups(session_id, group_number, enabled)
select id, 1, true from beacon_private.game_sessions where name = 'Saturday crew';
do $$ begin
    if (select inventory from beacon_private.game_session_groups gr
        join beacon_private.game_sessions s on s.id = gr.session_id
        where s.name = 'Saturday crew' and gr.group_number = 1) <> '[]'::jsonb
        or (select world_state ->> 'clock' from beacon_private.game_session_state st
            join beacon_private.game_sessions s on s.id = st.session_id where s.name = 'Friday crew') <> '2' then
        raise exception 'session state is not isolated';
    end if;
end $$;

set local role anon;
do $$
declare catalog text;
begin
    catalog := public.game_list_published()::text;
    if catalog not like '%Ghost Ship%' or catalog not like '%Beacon 3A-R3D%'
        or catalog like '%Unpublished secret%' or catalog like '%4821%' or catalog like '%hidden_log%' then
        raise exception 'catalog leaked private data or omitted published games: %', catalog;
    end if;
    if public.beacon_join_player('ABCDE')->>'code' <> repeat('a', 64) then
        raise exception 'legacy short code stopped working';
    end if;
    begin
        perform * from beacon_private.game_versions;
        raise exception 'anonymous user accessed game definitions';
    exception when insufficient_privilege then null; end;
    begin
        perform * from beacon_private.game_session_groups;
        raise exception 'anonymous user accessed private inventories';
    exception when insufficient_privilege then null; end;
    begin
        perform public.game_list_my_sessions();
        raise exception 'anonymous user listed sessions';
    exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
set local role authenticated;
do $$
declare sessions jsonb; opened jsonb;
begin
    sessions := public.game_list_my_sessions();
    opened := public.beacon_open_warden();
    if jsonb_array_length(sessions) <> 3 or sessions::text not like '%Friday crew%'
        or sessions::text not like '%Saturday crew%' or sessions::text like '%4821%'
        or sessions::text like '%' || repeat('a', 64) || '%'
        or opened ->> 'code' <> repeat('a', 64) or opened ->> 'player_code' <> 'ABCDE' then
        raise exception 'session listing or legacy Warden access incorrect: %', sessions;
    end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', true);
set local role authenticated;
do $$ begin
    if jsonb_array_length(public.game_list_my_sessions()) <> 1
        or public.game_list_my_sessions()::text like '%Friday crew%' then
        raise exception 'session listing exposed another Warden';
    end if;
end $$;
rollback;
