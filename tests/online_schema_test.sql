-- Run against an isolated test database after loading supabase/schema.sql.
-- The test database must provide mock auth.users, auth.uid(), anon and authenticated.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values ('11111111-1111-4111-8111-111111111111');
insert into beacon_private.sessions (owner_id, join_code, shared)
values ('11111111-1111-4111-8111-111111111111', repeat('a', 64),
    jsonb_build_object('vad_shared_station_state_v14', beacon_private.initial_rooms()));
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
set local role authenticated;
select set_config('test.code', public.beacon_open_warden()->>'code', true);
select set_config('test.player_code', public.beacon_open_warden()->>'player_code', true);
do $$
begin
    if current_setting('test.code') <> repeat('a', 64)
        or current_setting('test.player_code') !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{5}$'
        or public.beacon_open_warden()->>'player_code' <> current_setting('test.player_code') then
        raise exception 'player code is not five characters or not stable';
    end if;
end $$;
select public.beacon_update(current_setting('test.code'), null, 'vad_warden_notes_v1', '"PRIVATE NOTE"', 0);
select public.beacon_update(current_setting('test.code'), null, 'vad_audio_archive_v1', '{"unlocked":[1]}', 0);
select public.beacon_set_group(current_setting('test.code'), 2, true);
do $$
declare data jsonb;
begin
    data := public.beacon_read_session(current_setting('test.code'), null);
    if data #>> '{presence,2,room}' <> '1' then
        raise exception 'newly enabled group did not use the sector 1 fallback';
    end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
declare session_data jsonb;
begin
    if public.beacon_join_player(current_setting('test.player_code'))->>'code' <> current_setting('test.code') then
        raise exception 'player code did not resolve to the existing session';
    end if;
    begin
        perform public.beacon_join_player('INVALID');
        raise exception 'invalid player code was accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.beacon_join_player('AAAAA' || 'A');
        raise exception 'long player code was accepted';
    exception when invalid_parameter_value then null; end;
    session_data := public.beacon_read_session(current_setting('test.code'), 2);
    if session_data -> 'private' <> '{}'::jsonb then raise exception 'private data exposed'; end if;
    begin
        perform public.beacon_set_group(current_setting('test.code'), 3, true);
        raise exception 'anonymous user enabled group';
    exception when insufficient_privilege then null; end;
    begin
        perform public.beacon_update(current_setting('test.code'), 2, 'vad_warden_notes_v1', '"LEAK"', 0);
        raise exception 'anonymous user modified notes';
    exception when insufficient_privilege then null; end;
    begin
        perform public.beacon_update(current_setting('test.code'), 2, 'vad_shared_station_state_v14',
            '{"8":{"wardenAllowPickup":true}}', 0);
        raise exception 'anonymous user modified Warden permission';
    exception when insufficient_privilege then null; end;
    session_data := public.beacon_read_session(current_setting('test.code'), 3);
    if session_data #>> '{groups,3}' <> 'false' then raise exception 'disabled group not reported'; end if;
    begin
        perform public.beacon_update(current_setting('test.code'), 3, 'vad_shared_station_state_v14',
            '{"2":{"explored":true}}', 0);
        raise exception 'disabled group modified state';
    exception when insufficient_privilege then null; end;
    begin
        perform * from beacon_private.sessions;
        raise exception 'anonymous user read private table';
    exception when insufficient_privilege then null; end;
end $$;
select public.beacon_update(current_setting('test.code'), 2, 'vad_ship_status_v1', '{"power":100}', 0);
reset role;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
set local role authenticated;
select public.beacon_update(current_setting('test.code'), null, 'vad_shared_station_state_v14', '{"2":{"explored":true},"3":{"searched":true}}', 0);
select public.beacon_set_group(current_setting('test.code'), 3, true);
select public.beacon_set_group(current_setting('test.code'), 4, true);
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select public.beacon_focus(current_setting('test.code'), 2, '3', 0);
select public.beacon_focus(current_setting('test.code'), 1, '4', 0);
select public.beacon_focus(current_setting('test.code'), 3, '5', 0);
select public.beacon_focus(current_setting('test.code'), 4, '6', 0);
select public.beacon_log(current_setting('test.code'), 2, 'PLAYER', 'Explored sector 3', 0, '22222222-2222-4222-8222-222222222222');
select public.beacon_log(current_setting('test.code'), 2, 'PLAYER', 'Explored sector 3', 0, '22222222-2222-4222-8222-222222222222');
select public.beacon_log(current_setting('test.code'), 1, 'PLAYER', 'Searched sector 2', 0, '33333333-3333-4333-8333-333333333333');
reset role;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
set local role authenticated;
select public.beacon_log(current_setting('test.code'), null, 'WARDEN', 'Warden action', 0, '44444444-4444-4444-8444-444444444444');
do $$
declare data jsonb;
begin
    data := public.beacon_read_session(current_setting('test.code'), null);
    if data #>> '{shared,vad_shared_station_state_v14,2,explored}' <> 'true'
        or data #>> '{shared,vad_shared_station_state_v14,3,searched}' <> 'true'
        or data #>> '{shared,vad_ship_status_v1,power}' <> '100'
        or data #>> '{presence,2,room}' <> '3'
        or data #>> '{private,vad_warden_notes_v1}' <> 'PRIVATE NOTE'
        or data #>> '{private,vad_session_log_v1,0,m}' <> 'Explored sector 3'
        or data #> '{private,vad_session_log_v1,0,group}' is distinct from '2'::jsonb
        or data #> '{private,vad_session_log_v1,1,group}' is distinct from '1'::jsonb
        or data #> '{private,vad_session_log_v1,2,group}' is not null
        or jsonb_array_length(data #> '{private,vad_session_log_v1}') <> 3 then
        raise exception 'shared, presence or private data incorrect: %', data;
    end if;
    perform set_config('test.log', (data #> '{private,vad_session_log_v1}')::text, true);
    data := public.beacon_read_session(current_setting('test.code'), 2);
    if data -> 'private' <> '{}'::jsonb then raise exception 'group received Warden data'; end if;
    begin
        perform public.beacon_update(current_setting('test.code'), 2, 'vad_warden_notes_v1', '"NOT ALLOWED"', 0);
        raise exception 'group inherited Warden permissions';
    exception when insufficient_privilege then null; end;
end $$;
select public.beacon_reset(current_setting('test.code'));
do $$
declare data jsonb;
begin
    data := public.beacon_read_session(current_setting('test.code'), null);
    if data #>> '{shared,vad_shared_station_state_v14,2,explored}' <> 'false'
        or data -> 'shared' ? 'vad_audio_archive_v1'
        or data #>> '{private,vad_warden_notes_v1}' <> 'PRIVATE NOTE'
        or data #>> '{private,vad_session_log_v1,0,m}' <> 'Station reset'
        or data #>> '{presence,1,room}' <> '1'
        or data #>> '{presence,2,room}' <> '1'
        or data #>> '{presence,3,room}' <> '1'
        or data #>> '{presence,4,room}' <> '1'
        or data #>> '{groups,2}' <> 'true'
        or data #>> '{groups,3}' <> 'true'
        or data #>> '{groups,4}' <> 'true'
        or data ->> 'reset_epoch' <> '1' then
        raise exception 'reset did not preserve the intended state: %', data;
    end if;
    begin
        perform public.beacon_focus(current_setting('test.code'), 2, '3', 0);
        raise exception 'stale movement survived reset';
    exception when insufficient_privilege then null; end;
    begin
        perform public.beacon_restore(current_setting('test.code'), '{"vad_shared_station_state_v14":{}}');
        raise exception 'invalid backup accepted';
    exception when invalid_parameter_value then null; end;
    begin
        perform public.beacon_update(current_setting('test.code'), null, 'vad_shared_station_state_v14',
            '{"2":{"explored":true}}', 0);
        raise exception 'stale update survived reset';
    exception when serialization_failure then null; end;
    perform public.beacon_restore(current_setting('test.code'), data -> 'shared' ||
        jsonb_set(data -> 'private', '{vad_session_log_v1}', current_setting('test.log')::jsonb ||
            '[{"t":123,"s":"PLAYER","m":"Older entry"}]'::jsonb));
    data := public.beacon_read_session(current_setting('test.code'), null);
    if data ->> 'reset_epoch' <> '2' or data #>> '{private,vad_warden_notes_v1}' <> 'PRIVATE NOTE'
        or data #> '{private,vad_session_log_v1,0,group}' is distinct from '2'::jsonb
        or data #> '{private,vad_session_log_v1,1,group}' is distinct from '1'::jsonb
        or data #>> '{private,vad_session_log_v1,3,m}' <> 'Older entry' then
        raise exception 'valid backup restore failed: %', data;
    end if;
end $$;
select public.beacon_set_group(current_setting('test.code'), 2, false);
do $$
declare data jsonb;
begin
    data := public.beacon_read_session(current_setting('test.code'), 2);
    if data #>> '{groups,2}' <> 'false' or data #>> '{presence,2,room}' <> '1' then
        raise exception 'disabled group did not retain its last location';
    end if;
end $$;
select public.beacon_set_group(current_setting('test.code'), 2, true);
do $$
declare data jsonb;
begin
    data := public.beacon_read_session(current_setting('test.code'), 1);
    if data #>> '{groups,2}' <> 'true' or data #>> '{presence,2,room}' <> '1'
        or data -> 'private' <> '{}'::jsonb then
        raise exception 're-enabled group did not start at Group 1 or exposed Warden data';
    end if;
end $$;
select public.beacon_set_group(current_setting('test.code'), 2, false);
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $$
begin
    begin
        perform public.beacon_focus(current_setting('test.code'), 2, '3', 2);
        raise exception 'disabled group still updates focus';
    exception when insufficient_privilege then null; end;
    begin
        perform public.beacon_reset(current_setting('test.code'));
        raise exception 'anonymous user reset session';
    exception when insufficient_privilege then null; end;
end $$;
rollback;
