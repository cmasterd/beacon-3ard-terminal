-- Online session storage. Run as the project owner in the Supabase SQL editor.
-- The browser never has direct access to these tables.
create schema if not exists beacon_private;
revoke all on schema beacon_private from public, anon, authenticated;

create table if not exists beacon_private.sessions (
    owner_id uuid primary key references auth.users(id) on delete cascade,
    join_code text not null unique,
    shared jsonb not null default '{}'::jsonb,
    private_data jsonb not null default '{}'::jsonb,
    groups jsonb not null default '{"1":true,"2":false,"3":false,"4":false}'::jsonb,
    presence jsonb not null default '{}'::jsonb
);
alter table beacon_private.sessions add column if not exists reset_epoch bigint not null default 0;
alter table beacon_private.sessions add column if not exists player_code text;
alter table beacon_private.sessions add column if not exists action_requests jsonb not null default '[]'::jsonb;
create unique index if not exists beacon_sessions_player_code_idx on beacon_private.sessions (player_code);
alter table beacon_private.sessions enable row level security;
revoke all on all tables in schema beacon_private from public, anon, authenticated;

create or replace function beacon_private.initial_rooms()
returns jsonb language sql immutable set search_path = pg_catalog as $$
    select jsonb_object_agg(room, jsonb_build_object(
        'unlocked', room not in ('5', '6', '7', '8', '10'),
        'explored', room = '1',
        'searched', false, 'logUnlocked', false,
        'engineCollected', false, 'enginePowered', false,
        'wardenAllowPickup', false, 'wardenAllowPlug', false,
        'wardenAllow7bVis', false
    ))
    from unnest(array['1','2','3','4','5','6','7','7b','8','9','10']) room;
$$;

create or replace function public.beacon_open_warden()
returns jsonb
language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare
    session_row beacon_private.sessions%rowtype;
    alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    random_bits bigint;
    candidate text;
    i integer;
begin
    if auth.uid() is null then raise exception 'Warden login required' using errcode = '42501'; end if;
    insert into beacon_private.sessions (owner_id, join_code, shared)
    values (auth.uid(), replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
        jsonb_build_object('vad_shared_station_state_v14', beacon_private.initial_rooms()))
    on conflict (owner_id) do nothing;
    select * into session_row from beacon_private.sessions where owner_id = auth.uid() for update;
    if session_row.player_code is null then
        loop
            random_bits := ('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 7))::bit(28)::bigint;
            candidate := '';
            for i in 0..4 loop
                candidate := candidate || substr(alphabet, ((random_bits >> (i * 5)) & 31)::integer + 1, 1);
            end loop;
            begin
                update beacon_private.sessions set player_code = candidate
                where owner_id = auth.uid();
                exit;
            exception when unique_violation then
                continue;
            end;
        end loop;
        session_row.player_code := candidate;
    end if;
    return jsonb_build_object('code', session_row.join_code, 'player_code', session_row.player_code);
end;
$$;

create or replace function public.beacon_join_player(p_player_code text)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare session_code text;
begin
    if p_player_code is null or p_player_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{5}$' then
        raise exception 'Invalid session code' using errcode = '22023';
    end if;
    select join_code into session_code from beacon_private.sessions where player_code = p_player_code;
    if not found then raise exception 'Session code not found' using errcode = '42501'; end if;
    return jsonb_build_object('code', session_code);
end;
$$;

create or replace function public.beacon_read_session(p_code text, p_group integer)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare session_row beacon_private.sessions%rowtype; is_owner boolean;
begin
    select * into session_row from beacon_private.sessions where join_code = p_code;
    if not found then raise exception 'Session not found' using errcode = '42501'; end if;
    is_owner := p_group is null and auth.uid() is not null and auth.uid() = session_row.owner_id;
    if not is_owner and (p_group is null or p_group not between 1 and 4) then
        raise exception 'Invalid player group' using errcode = '42501';
    end if;
    return jsonb_build_object('shared', session_row.shared, 'groups', session_row.groups,
        'presence', session_row.presence,
        'action_requests', session_row.action_requests,
        'private', case when is_owner then session_row.private_data else '{}'::jsonb end,
        'reset_epoch', session_row.reset_epoch,
        'server_time', extract(epoch from clock_timestamp()) * 1000);
end;
$$;

create or replace function beacon_private.action_field(p_action text)
returns text language sql immutable set search_path = pg_catalog
as $$ select case p_action when 'explore' then 'explored' when 'search' then 'searched' when 'log' then 'logUnlocked' end $$;

create or replace function beacon_private.check_action(p_shared jsonb, p_room text, p_action text)
returns void language plpgsql set search_path = pg_catalog, beacon_private
as $$
declare room jsonb; field text;
begin
    field := beacon_private.action_field(p_action);
    if p_room is null or p_room not in ('1','2','3','4','5','6','7','7b','8','9','10') or field is null then
        raise exception 'Invalid action or sector' using errcode = '22023';
    end if;
    room := p_shared #> array['vad_shared_station_state_v14', p_room];
    if room is null or room ->> 'unlocked' is distinct from 'true'
        or (p_room = '7b' and room ->> 'enginePowered' is distinct from 'true' and room ->> 'wardenAllow7bVis' is distinct from 'true')
        or (p_action <> 'explore' and room ->> 'explored' is distinct from 'true')
        or room ->> field = 'true' then
        raise exception 'Action is unavailable or already completed' using errcode = '22023';
    end if;
end;
$$;

create or replace function public.beacon_request_action(p_code text, p_group integer, p_room text, p_action text, p_id uuid, p_epoch bigint)
returns void language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare session_row beacon_private.sessions%rowtype; entry jsonb; entries jsonb;
begin
    select * into session_row from beacon_private.sessions where join_code = p_code for update;
    if not found or p_group is null or p_group not between 1 and 4 or session_row.groups ->> p_group::text is distinct from 'true' then
        raise exception 'Active player group required' using errcode = '42501';
    end if;
    if p_epoch is distinct from session_row.reset_epoch then
        raise exception 'Session changed; reload before requesting' using errcode = '40001';
    end if;
    if p_id is null then raise exception 'Request identifier required' using errcode = '22023'; end if;
    select value into entry from jsonb_array_elements(session_row.action_requests) where value ->> 'id' = p_id::text;
    if found then
        if entry ->> 'group' <> p_group::text or entry ->> 'room' is distinct from p_room or entry ->> 'action' is distinct from p_action then
            raise exception 'Request identifier already used' using errcode = '22023';
        end if;
        return;
    end if;
    perform beacon_private.check_action(session_row.shared, p_room, p_action);
    if exists (select 1 from jsonb_array_elements(session_row.action_requests) e
        where e ->> 'status' = 'pending' and e ->> 'room' = p_room and e ->> 'action' = p_action) then
        raise exception 'An equivalent request is already pending' using errcode = '22023';
    end if;
    entries := session_row.action_requests;
    if jsonb_array_length(entries) >= 300 then
        select coalesce(jsonb_agg(value order by ord), '[]'::jsonb) into entries
        from jsonb_array_elements(entries) with ordinality t(value,ord) where value ->> 'status' = 'pending';
        if jsonb_array_length(entries) >= 300 then raise exception 'Request queue is full' using errcode = '54000'; end if;
    end if;
    update beacon_private.sessions set action_requests = entries || jsonb_build_array(jsonb_build_object(
        'id', p_id, 'group', p_group, 'room', p_room, 'action', p_action,
        'status', 'pending', 'time', extract(epoch from clock_timestamp()) * 1000))
    where owner_id = session_row.owner_id;
end;
$$;

create or replace function public.beacon_decide_action(p_code text, p_id uuid, p_approve boolean, p_epoch bigint)
returns void language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare session_row beacon_private.sessions%rowtype; entry jsonb; idx integer; field text; log jsonb; message text;
begin
    select * into session_row from beacon_private.sessions where join_code = p_code and owner_id = auth.uid() for update;
    if not found then raise exception 'Warden access required' using errcode = '42501'; end if;
    if p_epoch is distinct from session_row.reset_epoch then raise exception 'Session changed; reload' using errcode = '40001'; end if;
    if p_approve is null then raise exception 'Decision required' using errcode = '22023'; end if;
    select value, (ord - 1)::integer into entry, idx from jsonb_array_elements(session_row.action_requests) with ordinality t(value,ord)
        where value ->> 'id' = p_id::text;
    if entry is null then raise exception 'Request not found' using errcode = '22023'; end if;
    if entry ->> 'status' <> 'pending' then
        if entry ->> 'status' = (case when p_approve then 'approved' else 'rejected' end) then return; end if;
        raise exception 'Request already decided' using errcode = '22023';
    end if;
    if p_approve then
        perform beacon_private.check_action(session_row.shared, entry ->> 'room', entry ->> 'action');
        field := beacon_private.action_field(entry ->> 'action');
        session_row.shared := jsonb_set(session_row.shared, array['vad_shared_station_state_v14', entry ->> 'room', field], 'true'::jsonb);
        message := case entry ->> 'action' when 'explore' then 'Explored sector ' when 'search' then 'Searched sector ' else 'Accessed data log: sector ' end || (entry ->> 'room');
        log := coalesce(session_row.private_data -> 'vad_session_log_v1', '[]'::jsonb) || jsonb_build_array(
            jsonb_build_object('t', extract(epoch from clock_timestamp()) * 1000, 's', 'PLAYER', 'm', message, 'group', (entry ->> 'group')::integer));
        if jsonb_array_length(log) > 300 then log := log - 0; end if;
        session_row.private_data := jsonb_set(session_row.private_data, '{vad_session_log_v1}', log, true);
    end if;
    session_row.action_requests := jsonb_set(session_row.action_requests, array[idx::text, 'status'],
        to_jsonb(case when p_approve then 'approved' else 'rejected' end));
    update beacon_private.sessions set shared = session_row.shared, private_data = session_row.private_data,
        action_requests = session_row.action_requests where owner_id = session_row.owner_id;
end;
$$;

create or replace function public.beacon_set_group(p_code text, p_group integer, p_enabled boolean)
returns void
language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
begin
    if auth.uid() is null or p_group is null or p_group not between 2 and 4 or p_enabled is null then
        raise exception 'Invalid group or Warden login' using errcode = '42501';
    end if;
    update beacon_private.sessions
    set groups = jsonb_set(groups, array[p_group::text], to_jsonb(p_enabled)),
        presence = case when p_enabled and groups ->> p_group::text is distinct from 'true'
            then jsonb_set(presence, array[p_group::text],
                jsonb_build_object('room', coalesce(presence #>> '{1,room}', '1'),
                    'time', extract(epoch from clock_timestamp()) * 1000), true)
            else presence end
    where join_code = p_code and owner_id = auth.uid();
    if not found then raise exception 'Warden access required' using errcode = '42501'; end if;
end;
$$;

drop function if exists public.beacon_focus(text, integer, text);
create or replace function public.beacon_focus(p_code text, p_group integer, p_room text, p_epoch bigint)
returns void
language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
begin
    if p_group is null or p_group not between 1 and 4 or p_room is null or
        p_room not in ('1','2','3','4','5','6','7','7b','8','9','10') then
        raise exception 'Invalid group or sector' using errcode = '22023';
    end if;
    update beacon_private.sessions
    set presence = jsonb_set(presence, array[p_group::text],
        jsonb_build_object('room', p_room, 'time', extract(epoch from clock_timestamp()) * 1000), true)
    where join_code = p_code and groups ->> p_group::text = 'true' and reset_epoch = p_epoch;
    if not found then
        raise exception 'Session, active group or reset version is invalid; reload before moving' using errcode = '42501';
    end if;
end;
$$;

drop function if exists public.beacon_update(text, integer, text, jsonb);
create or replace function public.beacon_update(p_code text, p_group integer, p_key text, p_value jsonb, p_epoch bigint)
returns void
language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare
    session_row beacon_private.sessions%rowtype;
    is_owner boolean;
    room_entry record;
    field_entry record;
    result jsonb;
begin
    select * into session_row from beacon_private.sessions where join_code = p_code for update;
    if not found then raise exception 'Session not found' using errcode = '42501'; end if;
    is_owner := p_group is null and auth.uid() is not null and auth.uid() = session_row.owner_id;
    if not is_owner and (p_group is null or p_group not between 1 and 4 or
        session_row.groups ->> p_group::text is distinct from 'true') then
        raise exception 'Group is not active' using errcode = '42501';
    end if;
    if p_key is null or (p_value is not null and length(p_value::text) > 100000) then
        raise exception 'Invalid update' using errcode = '22023';
    end if;
    if p_epoch is distinct from session_row.reset_epoch then
        raise exception 'Session was reset or restored; reload before making changes' using errcode = '40001';
    end if;

    if p_key = 'vad_shared_station_state_v14' then
        if jsonb_typeof(p_value) is distinct from 'object' then
            raise exception 'Expected room changes' using errcode = '22023';
        end if;
        result := session_row.shared -> p_key;
        for room_entry in select * from jsonb_each(p_value) loop
            if room_entry.key not in ('1','2','3','4','5','6','7','7b','8','9','10')
                or jsonb_typeof(room_entry.value) <> 'object' then
                raise exception 'Invalid room' using errcode = '22023';
            end if;
            for field_entry in select * from jsonb_each(room_entry.value) loop
                if field_entry.key not in ('unlocked','explored','searched','logUnlocked',
                    'engineCollected','enginePowered','wardenAllowPickup','wardenAllowPlug','wardenAllow7bVis')
                    or jsonb_typeof(field_entry.value) <> 'boolean' then
                    raise exception 'Invalid room field' using errcode = '22023';
                end if;
                if not is_owner and (field_entry.key in ('explored','searched','logUnlocked') or field_entry.key like 'warden%'
                    or field_entry.value <> 'true'::jsonb
                    or (field_entry.key = 'engineCollected' and room_entry.key <> '8')
                    or (field_entry.key = 'enginePowered' and room_entry.key <> '7b')) then
                    raise exception 'Warden access required for this change' using errcode = '42501';
                end if;
                result := jsonb_set(result, array[room_entry.key, field_entry.key], field_entry.value, true);
            end loop;
        end loop;
        session_row.shared := jsonb_set(session_row.shared, array[p_key], result, true);
    elsif p_key = 'vad_ship_status_v1' then
        if p_value is null and is_owner then
            session_row.shared := session_row.shared - p_key;
        else
            if jsonb_typeof(p_value) is distinct from 'object' then
                raise exception 'Invalid status' using errcode = '22023';
            end if;
            if not is_owner and (p_value - 'power' <> '{}'::jsonb
                or p_value -> 'power' is distinct from '100'::jsonb) then
                raise exception 'Player can only restore engine power' using errcode = '42501';
            end if;
            for field_entry in select * from jsonb_each(p_value) loop
                if field_entry.key not in ('oxygen','power','hull','comms')
                    or jsonb_typeof(field_entry.value) <> 'number'
                    or (field_entry.value::text)::numeric not between 0 and 100 then
                    raise exception 'Invalid status field' using errcode = '22023';
                end if;
            end loop;
            result := coalesce(session_row.shared -> p_key, '{"oxygen":100,"power":0,"hull":100,"comms":0}'::jsonb);
            session_row.shared := jsonb_set(session_row.shared, array[p_key], result || p_value, true);
        end if;
    elsif p_key in ('vad_hazards_v1','vad_audio_archive_v1',
        'vad_video_archive_v1','vad_text_archive_v1','vad_broadcast_v1','vad_countdown_v1') then
        if not is_owner then raise exception 'Warden access required' using errcode = '42501'; end if;
        if p_value is null then
            session_row.shared := session_row.shared - p_key;
        else
            session_row.shared := jsonb_set(session_row.shared, array[p_key], p_value, true);
        end if;
    elsif p_key = 'vad_warden_notes_v1' then
        if not is_owner then raise exception 'Warden access required' using errcode = '42501'; end if;
        if p_value is null then
            session_row.private_data := session_row.private_data - p_key;
        else
            session_row.private_data := jsonb_set(session_row.private_data, array[p_key], p_value, true);
        end if;
    else
        raise exception 'Unsupported key' using errcode = '22023';
    end if;
    update beacon_private.sessions set shared = session_row.shared, private_data = session_row.private_data
    where owner_id = session_row.owner_id;
end;
$$;

drop function if exists public.beacon_log(text, integer, text, text);
drop function if exists public.beacon_log(text, integer, text, text, bigint);
create or replace function public.beacon_log(p_code text, p_group integer, p_source text, p_message text, p_epoch bigint, p_event_id uuid)
returns void
language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare session_row beacon_private.sessions%rowtype; is_owner boolean; entries jsonb;
begin
    select * into session_row from beacon_private.sessions where join_code = p_code for update;
    if not found then raise exception 'Session not found' using errcode = '42501'; end if;
    is_owner := p_group is null and auth.uid() is not null and auth.uid() = session_row.owner_id;
    if not is_owner and (p_group is null or p_group not between 1 and 4 or
        session_row.groups ->> p_group::text is distinct from 'true') then
        raise exception 'Group is not active' using errcode = '42501';
    end if;
    if p_epoch is distinct from session_row.reset_epoch then
        raise exception 'Session was reset or restored; reload before making changes' using errcode = '40001';
    end if;
    if p_event_id is null or p_source is null or p_source not in ('PLAYER', 'WARDEN') or (p_source = 'WARDEN' and not is_owner)
        or p_message is null or length(p_message) > 1000 then
        raise exception 'Invalid log entry' using errcode = '42501';
    end if;
    entries := coalesce(session_row.private_data -> 'vad_session_log_v1', '[]'::jsonb);
    if exists (select 1 from jsonb_array_elements(entries) as existing
        where existing ->> 'id' = p_event_id::text) then return; end if;
    entries := entries || jsonb_build_array(jsonb_build_object('t', extract(epoch from clock_timestamp()) * 1000,
        's', p_source, 'm', p_message, 'id', p_event_id) ||
        case when p_source = 'PLAYER' and p_group is not null
            then jsonb_build_object('group', p_group) else '{}'::jsonb end);
    if jsonb_array_length(entries) > 300 then entries := entries - 0; end if;
    update beacon_private.sessions set private_data = jsonb_set(private_data,
        array['vad_session_log_v1'], entries, true) where owner_id = session_row.owner_id;
end;
$$;

drop function if exists public.beacon_clear_log(text);
create or replace function public.beacon_clear_log(p_code text, p_epoch bigint)
returns void
language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
begin
    update beacon_private.sessions set private_data = private_data - 'vad_session_log_v1'
    where join_code = p_code and owner_id = auth.uid() and reset_epoch = p_epoch;
    if not found then raise exception 'Warden access required' using errcode = '42501'; end if;
end;
$$;

create or replace function public.beacon_restore(p_code text, p_data jsonb)
returns void
language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare
    rooms jsonb;
    room text;
    field text;
    key text;
    new_shared jsonb := '{}'::jsonb;
    new_private jsonb := '{}'::jsonb;
    entry jsonb;
begin
    if auth.uid() is null or not exists (
        select 1 from beacon_private.sessions where join_code = p_code and owner_id = auth.uid()
    ) then raise exception 'Warden access required' using errcode = '42501'; end if;
    if jsonb_typeof(p_data) is distinct from 'object' or length(p_data::text) > 200000 then
        raise exception 'Invalid backup' using errcode = '22023';
    end if;
    rooms := coalesce(p_data -> 'vad_shared_station_state_v14', beacon_private.initial_rooms());
    if jsonb_typeof(rooms) is distinct from 'object' then raise exception 'Invalid rooms' using errcode = '22023'; end if;
    foreach room in array array['1','2','3','4','5','6','7','7b','8','9','10'] loop
        if jsonb_typeof(rooms -> room) is distinct from 'object' then raise exception 'Missing room %', room using errcode = '22023'; end if;
        foreach field in array array['unlocked','explored','searched','logUnlocked','engineCollected',
            'enginePowered','wardenAllowPickup','wardenAllowPlug','wardenAllow7bVis'] loop
            if jsonb_typeof(rooms -> room -> field) is distinct from 'boolean' then
                raise exception 'Invalid room field %', field using errcode = '22023';
            end if;
        end loop;
    end loop;
    new_shared := jsonb_build_object('vad_shared_station_state_v14', rooms);
    foreach key in array array['vad_ship_status_v1','vad_hazards_v1','vad_audio_archive_v1',
        'vad_video_archive_v1','vad_text_archive_v1','vad_broadcast_v1','vad_countdown_v1'] loop
        if p_data ? key then
            if jsonb_typeof(p_data -> key) is distinct from 'object' then
                raise exception 'Invalid backup entry %', key using errcode = '22023';
            end if;
            new_shared := jsonb_set(new_shared, array[key], p_data -> key, true);
        end if;
    end loop;
    if p_data ? 'vad_warden_notes_v1' then
        if jsonb_typeof(p_data -> 'vad_warden_notes_v1') is distinct from 'string' then
            raise exception 'Invalid notes' using errcode = '22023';
        end if;
        new_private := jsonb_set(new_private, array['vad_warden_notes_v1'], p_data -> 'vad_warden_notes_v1', true);
    end if;
    if p_data ? 'vad_session_log_v1' then
        if jsonb_typeof(p_data -> 'vad_session_log_v1') is distinct from 'array'
            or jsonb_array_length(p_data -> 'vad_session_log_v1') > 300 then
            raise exception 'Invalid session log' using errcode = '22023';
        end if;
        for entry in select * from jsonb_array_elements(p_data -> 'vad_session_log_v1') loop
            if jsonb_typeof(entry -> 't') is distinct from 'number'
                or coalesce(entry ->> 's', '') not in ('WARDEN','PLAYER')
                or jsonb_typeof(entry -> 'm') is distinct from 'string'
                or length(entry ->> 'm') > 1000
                or (entry ? 'group' and (entry ->> 's' <> 'PLAYER'
                    or entry -> 'group' not in ('1'::jsonb, '2'::jsonb, '3'::jsonb, '4'::jsonb))) then
                raise exception 'Invalid session log entry' using errcode = '22023';
            end if;
        end loop;
        new_private := jsonb_set(new_private, array['vad_session_log_v1'], p_data -> 'vad_session_log_v1', true);
    end if;
    update beacon_private.sessions set shared = new_shared, private_data = new_private, action_requests = '[]'::jsonb, reset_epoch = reset_epoch + 1
    where join_code = p_code and owner_id = auth.uid();
end;
$$;

create or replace function public.beacon_reset(p_code text)
returns void
language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
begin
    update beacon_private.sessions
    set shared = jsonb_build_object('vad_shared_station_state_v14', beacon_private.initial_rooms()),
        presence = presence || (select jsonb_object_agg(group_id, jsonb_build_object(
            'room', '1', 'time', extract(epoch from clock_timestamp()) * 1000))
            from unnest(array['1','2','3','4']) as group_id
            where groups ->> group_id = 'true'),
        private_data = (private_data - 'vad_session_log_v1') || jsonb_build_object('vad_session_log_v1',
            jsonb_build_array(jsonb_build_object('t', extract(epoch from clock_timestamp()) * 1000,
                's', 'WARDEN', 'm', 'Station reset'))),
        action_requests = '[]'::jsonb, reset_epoch = reset_epoch + 1
    where join_code = p_code and owner_id = auth.uid();
    if not found then raise exception 'Warden access required' using errcode = '42501'; end if;
end;
$$;

-- Only these RPCs are exposed; policies and client-side UI are not the access boundary.
revoke all on function public.beacon_open_warden() from public, anon;
revoke all on function public.beacon_join_player(text) from public;
revoke all on function public.beacon_read_session(text, integer) from public;
revoke all on function public.beacon_set_group(text, integer, boolean) from public, anon;
revoke all on function public.beacon_focus(text, integer, text, bigint) from public;
revoke all on function public.beacon_update(text, integer, text, jsonb, bigint) from public;
revoke all on function public.beacon_log(text, integer, text, text, bigint, uuid) from public;
revoke all on function public.beacon_clear_log(text, bigint) from public, anon;
revoke all on function public.beacon_restore(text, jsonb) from public, anon;
revoke all on function public.beacon_reset(text) from public, anon;
revoke all on function public.beacon_request_action(text, integer, text, text, uuid, bigint) from public;
revoke all on function public.beacon_decide_action(text, uuid, boolean, bigint) from public, anon;
grant execute on function public.beacon_open_warden() to authenticated;
grant execute on function public.beacon_join_player(text) to anon, authenticated;
grant execute on function public.beacon_read_session(text, integer) to anon, authenticated;
grant execute on function public.beacon_set_group(text, integer, boolean) to authenticated;
grant execute on function public.beacon_focus(text, integer, text, bigint) to anon, authenticated;
grant execute on function public.beacon_update(text, integer, text, jsonb, bigint) to anon, authenticated;
grant execute on function public.beacon_log(text, integer, text, text, bigint, uuid) to anon, authenticated;
grant execute on function public.beacon_clear_log(text, bigint) to authenticated;
grant execute on function public.beacon_restore(text, jsonb) to authenticated;
grant execute on function public.beacon_reset(text) to authenticated;
grant execute on function public.beacon_request_action(text, integer, text, text, uuid, bigint) to anon, authenticated;
grant execute on function public.beacon_decide_action(text, uuid, boolean, bigint) to authenticated;
