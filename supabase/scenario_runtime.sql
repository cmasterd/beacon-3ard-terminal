-- Experimental scenario action foundation. Apply after game_foundation.sql
-- only in an isolated test project. This does not provide a playable terminal.
begin;

create table if not exists beacon_private.scenario_access (
    session_id uuid primary key references beacon_private.game_sessions(id) on delete cascade,
    player_code text not null unique
);
create table if not exists beacon_private.scenario_progress (
    session_id uuid not null references beacon_private.game_sessions(id) on delete cascade,
    node_id text not null,
    explored boolean not null default false,
    searched boolean not null default false,
    logs_accessed boolean not null default false,
    primary key (session_id, node_id)
);
create table if not exists beacon_private.scenario_action_requests (
    session_id uuid not null references beacon_private.game_sessions(id) on delete cascade,
    request_id uuid not null,
    group_number integer not null check (group_number between 1 and 4),
    node_id text not null,
    action text not null check (action in ('explore', 'search', 'log')),
    status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
    created_at timestamptz not null default clock_timestamp(),
    primary key (session_id, request_id)
);
create unique index if not exists scenario_pending_action_idx
    on beacon_private.scenario_action_requests(session_id, node_id, action) where status = 'pending';
alter table beacon_private.scenario_access enable row level security;
alter table beacon_private.scenario_progress enable row level security;
alter table beacon_private.scenario_action_requests enable row level security;
revoke all on beacon_private.scenario_access, beacon_private.scenario_progress,
    beacon_private.scenario_action_requests from public, anon, authenticated;

-- Validate every field the player projection can ever expose. Draft saving
-- validates only the envelope, so activation must not trust a submitted file.
create or replace function beacon_private.validate_scenario_projection(p_package jsonb)
returns void language plpgsql set search_path = pg_catalog, beacon_private
as $$
declare nodes jsonb; node jsonb; item jsonb; log_entry jsonb; ids text[] := '{}';
begin
    if p_package #>> '{definition,format}' is distinct from 'vad-scenario'
        or p_package #> '{definition,version}' is distinct from '1'::jsonb
        or jsonb_typeof(p_package #> '{catalog,title}') is distinct from 'string'
        or jsonb_typeof(p_package #> '{definition,nodes}') is distinct from 'array' then
        raise exception 'Unsupported scenario definition' using errcode = '22023';
    end if;
    nodes := p_package #> '{definition,nodes}';
    if jsonb_array_length(nodes) = 0 then raise exception 'Scenario has no rooms' using errcode = '22023'; end if;
    for node in select value from jsonb_array_elements(nodes) loop
        if jsonb_typeof(node) is distinct from 'object'
            or jsonb_typeof(node -> 'id') is distinct from 'string'
            or node ->> 'id' !~ '^[a-zA-Z0-9_-]+$'
            or node ->> 'id' = any(ids)
            or jsonb_typeof(node -> 'name') is distinct from 'string'
            or jsonb_typeof(node -> 'level') is distinct from 'string'
            or jsonb_typeof(node -> 'description') is distinct from 'string'
            or jsonb_typeof(node -> 'status') is distinct from 'string'
            or jsonb_typeof(node -> 'isLocked') is distinct from 'boolean'
            or jsonb_typeof(node -> 'items') is distinct from 'array'
            or jsonb_typeof(node -> 'logs') is distinct from 'array' then
            raise exception 'Invalid room for scenario projection' using errcode = '22023';
        end if;
        ids := array_append(ids, node ->> 'id');
        for item in select value from jsonb_array_elements(node -> 'items') loop
            if jsonb_typeof(item) is distinct from 'object'
                or jsonb_typeof(item -> 'id') is distinct from 'string'
                or jsonb_typeof(item -> 'name') is distinct from 'string'
                or jsonb_typeof(item -> 'isHeavy') is distinct from 'boolean' then
                raise exception 'Invalid item for scenario projection' using errcode = '22023';
            end if;
        end loop;
        for log_entry in select value from jsonb_array_elements(node -> 'logs') loop
            if jsonb_typeof(log_entry) is distinct from 'object'
                or jsonb_typeof(log_entry -> 'id') is distinct from 'string'
                or jsonb_typeof(log_entry -> 'title') is distinct from 'string'
                or jsonb_typeof(log_entry -> 'author') is distinct from 'string'
                or jsonb_typeof(log_entry -> 'body') is distinct from 'string'
                or jsonb_typeof(log_entry -> 'stress') is distinct from 'number' then
                raise exception 'Invalid log for scenario projection' using errcode = '22023';
            end if;
        end loop;
    end loop;
end;
$$;

create or replace function public.scenario_activate_session(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare session_row beacon_private.game_sessions%rowtype; package jsonb; code text;
begin
    select * into session_row from beacon_private.game_sessions
        where id = p_session_id and owner_id = auth.uid() and legacy_owner_id is null for update;
    if not found then raise exception 'Warden session not found' using errcode = '42501'; end if;
    select definition into package from beacon_private.game_versions
        where id = session_row.version_id and game_id = session_row.game_id;
    perform beacon_private.validate_scenario_projection(package);
    if not exists (select 1 from beacon_private.game_session_groups where session_id = p_session_id and group_number = 1 and enabled) then
        raise exception 'Session has no enabled group 1' using errcode = '22023';
    end if;
    insert into beacon_private.scenario_access(session_id, player_code)
    values (p_session_id, replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''))
    on conflict (session_id) do nothing;
    select player_code into code from beacon_private.scenario_access where session_id = p_session_id;
    return jsonb_build_object('session_id', p_session_id, 'player_code', code);
end;
$$;

create or replace function public.scenario_player_view(p_code text, p_group integer)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, beacon_private
as $$
declare session_row beacon_private.game_sessions%rowtype; package jsonb; location text; rooms jsonb; requests jsonb;
begin
    select s.* into session_row from beacon_private.scenario_access a
        join beacon_private.game_sessions s on s.id = a.session_id where a.player_code = p_code;
    if not found or p_group is null or p_group not between 1 and 4 then
        raise exception 'Active player session required' using errcode = '42501';
    end if;
    select location_id into location from beacon_private.game_session_groups
        where session_id = session_row.id and group_number = p_group and enabled;
    if not found then raise exception 'Active player group required' using errcode = '42501'; end if;
    select definition into package from beacon_private.game_versions where id = session_row.version_id;
    select coalesce(jsonb_agg(
        jsonb_build_object('id', n ->> 'id', 'explored', coalesce(p.explored, false),
            'searched', coalesce(p.searched, false), 'logs_accessed', coalesce(p.logs_accessed, false))
        || case when p.explored then jsonb_build_object('name', n ->> 'name', 'level', n ->> 'level',
            'description', n ->> 'description', 'status', n ->> 'status') else '{}'::jsonb end
        || case when p.searched then jsonb_build_object('items', (select coalesce(jsonb_agg(jsonb_build_object(
            'id', i ->> 'id', 'name', i ->> 'name', 'isHeavy', i -> 'isHeavy')), '[]'::jsonb)
            from jsonb_array_elements(n -> 'items') i)) else '{}'::jsonb end
        || case when p.logs_accessed then jsonb_build_object('logs', (select coalesce(jsonb_agg(jsonb_build_object(
            'id', l ->> 'id', 'title', l ->> 'title', 'author', l ->> 'author',
            'body', l ->> 'body', 'stress', l -> 'stress')), '[]'::jsonb)
            from jsonb_array_elements(n -> 'logs') l)) else '{}'::jsonb end
        order by ord), '[]'::jsonb) into rooms
        from jsonb_array_elements(package #> '{definition,nodes}') with ordinality t(n, ord)
        left join beacon_private.scenario_progress p on p.session_id = session_row.id and p.node_id = n ->> 'id';
    select coalesce(jsonb_agg(jsonb_build_object('id', request_id, 'group', group_number,
        'node_id', node_id, 'action', action, 'status', status) order by created_at, request_id), '[]'::jsonb)
        into requests from beacon_private.scenario_action_requests where session_id = session_row.id;
    return jsonb_build_object('title', package #>> '{catalog,title}', 'group', p_group,
        'location', location, 'rooms', rooms, 'requests', requests);
end;
$$;

create or replace function public.scenario_move(p_code text, p_group integer, p_node_id text)
returns void language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare session_row beacon_private.game_sessions%rowtype;
begin
    select s.* into session_row from beacon_private.scenario_access a
        join beacon_private.game_sessions s on s.id = a.session_id where a.player_code = p_code for update of s;
    if not found then raise exception 'Active player session required' using errcode = '42501'; end if;
    if not exists (select 1 from beacon_private.game_versions v,
        jsonb_array_elements(v.definition #> '{definition,nodes}') n
        where v.id = session_row.version_id and n ->> 'id' = p_node_id) then
        raise exception 'Invalid room' using errcode = '22023';
    end if;
    update beacon_private.game_session_groups set location_id = p_node_id
        where session_id = session_row.id and group_number = p_group and enabled;
    if not found then raise exception 'Active player group required' using errcode = '42501'; end if;
end;
$$;

create or replace function beacon_private.check_scenario_action(p_session uuid, p_node text, p_action text)
returns void language plpgsql set search_path = pg_catalog, beacon_private
as $$
declare node jsonb; progress beacon_private.scenario_progress%rowtype;
begin
    if p_action is null or p_action not in ('explore','search','log') then
        raise exception 'Invalid action' using errcode = '22023';
    end if;
    select n into node from beacon_private.game_sessions s
        join beacon_private.game_versions v on v.id = s.version_id,
        jsonb_array_elements(v.definition #> '{definition,nodes}') n
        where s.id = p_session and n ->> 'id' = p_node;
    if node is null or node -> 'isLocked' is distinct from 'false'::jsonb then
        raise exception 'Room is unavailable or locked' using errcode = '22023';
    end if;
    select * into progress from beacon_private.scenario_progress where session_id = p_session and node_id = p_node;
    if (p_action <> 'explore' and not coalesce(progress.explored, false))
        or (p_action = 'explore' and coalesce(progress.explored, false))
        or (p_action = 'search' and coalesce(progress.searched, false))
        or (p_action = 'log' and coalesce(progress.logs_accessed, false)) then
        raise exception 'Action is unavailable or already completed' using errcode = '22023';
    end if;
end;
$$;

create or replace function public.scenario_request_action(p_code text, p_group integer, p_node text, p_action text, p_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare session_row beacon_private.game_sessions%rowtype; existing beacon_private.scenario_action_requests%rowtype;
begin
    select s.* into session_row from beacon_private.scenario_access a
        join beacon_private.game_sessions s on s.id = a.session_id where a.player_code = p_code for update of s;
    if not found or p_group is null or p_group not between 1 and 4 then
        raise exception 'Active player session required' using errcode = '42501';
    end if;
    if not exists (select 1 from beacon_private.game_session_groups
        where session_id = session_row.id and group_number = p_group and enabled) then
        raise exception 'Active player group required' using errcode = '42501';
    end if;
    if p_id is null then raise exception 'Request identifier required' using errcode = '22023'; end if;
    select * into existing from beacon_private.scenario_action_requests where session_id = session_row.id and request_id = p_id;
    if found then
        if existing.group_number is distinct from p_group or existing.node_id is distinct from p_node
            or existing.action is distinct from p_action then
            raise exception 'Request identifier already used' using errcode = '22023';
        end if;
        return;
    end if;
    if not exists (select 1 from beacon_private.game_session_groups
        where session_id = session_row.id and group_number = p_group and location_id = p_node) then
        raise exception 'Group must be in the requested room' using errcode = '22023';
    end if;
    perform beacon_private.check_scenario_action(session_row.id, p_node, p_action);
    if exists (select 1 from beacon_private.scenario_action_requests where session_id = session_row.id
        and node_id = p_node and action = p_action and status = 'pending') then
        raise exception 'An equivalent request is already pending' using errcode = '22023';
    end if;
    if (select count(*) from beacon_private.scenario_action_requests where session_id = session_row.id) >= 300 then
        raise exception 'Request history is full' using errcode = '54000';
    end if;
    insert into beacon_private.scenario_action_requests(session_id, request_id, group_number, node_id, action)
        values (session_row.id, p_id, p_group, p_node, p_action);
end;
$$;

create or replace function public.scenario_warden_requests(p_session_id uuid)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, beacon_private
as $$
begin
    if not exists (select 1 from beacon_private.game_sessions
        where id = p_session_id and owner_id = auth.uid() and legacy_owner_id is null) then
        raise exception 'Warden session not found' using errcode = '42501';
    end if;
    return coalesce((select jsonb_agg(jsonb_build_object('id', request_id, 'group', group_number,
        'node_id', node_id, 'action', action, 'status', status) order by created_at, request_id)
        from beacon_private.scenario_action_requests where session_id = p_session_id), '[]'::jsonb);
end;
$$;

create or replace function public.scenario_decide_action(p_session_id uuid, p_id uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = pg_catalog, beacon_private
as $$
declare request beacon_private.scenario_action_requests%rowtype; decision text;
begin
    perform 1 from beacon_private.game_sessions where id = p_session_id and owner_id = auth.uid()
        and legacy_owner_id is null for update;
    if not found then raise exception 'Warden session not found' using errcode = '42501'; end if;
    if p_approve is null then raise exception 'Decision required' using errcode = '22023'; end if;
    select * into request from beacon_private.scenario_action_requests where session_id = p_session_id and request_id = p_id;
    if not found then raise exception 'Request not found' using errcode = '22023'; end if;
    decision := case when p_approve then 'approved' else 'rejected' end;
    if request.status <> 'pending' then
        if request.status = decision then return; end if;
        raise exception 'Request already decided' using errcode = '22023';
    end if;
    if p_approve then
        perform beacon_private.check_scenario_action(p_session_id, request.node_id, request.action);
        insert into beacon_private.scenario_progress(session_id, node_id, explored, searched, logs_accessed)
            values (p_session_id, request.node_id, request.action = 'explore', request.action = 'search', request.action = 'log')
        on conflict (session_id, node_id) do update set
            explored = scenario_progress.explored or excluded.explored,
            searched = scenario_progress.searched or excluded.searched,
            logs_accessed = scenario_progress.logs_accessed or excluded.logs_accessed;
    end if;
    update beacon_private.scenario_action_requests set status = decision where session_id = p_session_id and request_id = p_id;
end;
$$;

revoke all on function beacon_private.validate_scenario_projection(jsonb) from public, anon, authenticated;
revoke all on function beacon_private.check_scenario_action(uuid, text, text) from public, anon, authenticated;
revoke all on function public.scenario_activate_session(uuid) from public, anon;
revoke all on function public.scenario_player_view(text, integer) from public;
revoke all on function public.scenario_move(text, integer, text) from public;
revoke all on function public.scenario_request_action(text, integer, text, text, uuid) from public;
revoke all on function public.scenario_warden_requests(uuid) from public, anon;
revoke all on function public.scenario_decide_action(uuid, uuid, boolean) from public, anon;
grant execute on function public.scenario_activate_session(uuid) to authenticated;
grant execute on function public.scenario_player_view(text, integer) to anon, authenticated;
grant execute on function public.scenario_move(text, integer, text) to anon, authenticated;
grant execute on function public.scenario_request_action(text, integer, text, text, uuid) to anon, authenticated;
grant execute on function public.scenario_warden_requests(uuid) to authenticated;
grant execute on function public.scenario_decide_action(uuid, uuid, boolean) to authenticated;
commit;
