-- Experimental game/session foundation. Apply after schema.sql, in an isolated
-- database first. Existing Beacon gameplay remains in beacon_private.sessions.
begin;

create table if not exists beacon_private.games (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid references auth.users(id) on delete cascade,
    title text not null check (length(btrim(title)) between 1 and 120),
    description text not null default '' check (length(description) <= 2000),
    engine text not null check (engine in ('beacon_legacy', 'scenario')),
    published boolean not null default false,
    created_at timestamptz not null default clock_timestamp()
);

-- Definitions and their secrets are never included in the public game catalog.
create table if not exists beacon_private.game_versions (
    id uuid primary key default gen_random_uuid(),
    game_id uuid not null references beacon_private.games(id) on delete cascade,
    version integer not null check (version > 0),
    definition jsonb not null check (jsonb_typeof(definition) = 'object'),
    created_at timestamptz not null default clock_timestamp(),
    unique (game_id, version),
    unique (game_id, id)
);

create table if not exists beacon_private.game_sessions (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    game_id uuid not null references beacon_private.games(id),
    name text not null check (length(btrim(name)) between 1 and 120),
    version_id uuid,
    legacy_owner_id uuid unique references beacon_private.sessions(owner_id) on delete cascade,
    created_at timestamptz not null default clock_timestamp(),
    foreign key (game_id, version_id) references beacon_private.game_versions(game_id, id),
    check (legacy_owner_id is null or (legacy_owner_id = owner_id and version_id is null
        and game_id = 'b3a00000-0000-4000-8000-000000000001')),
    check (legacy_owner_id is not null or version_id is not null)
);

create index if not exists game_sessions_owner_game_idx on beacon_private.game_sessions(owner_id, game_id);

-- Scenario runtime state is private until player-specific projections exist.
-- Legacy Beacon sessions continue to use their existing tables.
create table if not exists beacon_private.game_session_state (
    session_id uuid primary key references beacon_private.game_sessions(id) on delete cascade,
    world_state jsonb not null default '{}'::jsonb check (jsonb_typeof(world_state) = 'object'),
    ship_data jsonb check (ship_data is null or jsonb_typeof(ship_data) = 'object'),
    revision bigint not null default 0 check (revision >= 0)
);

create table if not exists beacon_private.game_session_groups (
    session_id uuid not null references beacon_private.game_sessions(id) on delete cascade,
    group_number integer not null check (group_number between 1 and 4),
    enabled boolean not null default false,
    location_id text,
    inventory jsonb not null default '[]'::jsonb check (jsonb_typeof(inventory) = 'array'),
    primary key (session_id, group_number)
);

alter table beacon_private.games enable row level security;
alter table beacon_private.game_versions enable row level security;
alter table beacon_private.game_sessions enable row level security;
alter table beacon_private.game_session_state enable row level security;
alter table beacon_private.game_session_groups enable row level security;
revoke all on beacon_private.games, beacon_private.game_versions, beacon_private.game_sessions,
    beacon_private.game_session_state, beacon_private.game_session_groups
    from public, anon, authenticated;

-- Reserve a stable ID for the built-in Beacon game; don't overwrite metadata on reruns.
insert into beacon_private.games (id, owner_id, title, description, engine, published)
values ('b3a00000-0000-4000-8000-000000000001', null, 'Beacon 3A-R3D',
    'Explore a silent station with player and Warden terminals.', 'beacon_legacy', true)
on conflict (id) do nothing;

-- The legacy session remains authoritative: the mapping contains no copied
-- credentials or state and cannot change its game or owner.
create or replace function beacon_private.register_beacon_session()
returns trigger language plpgsql security definer
set search_path = pg_catalog, beacon_private
as $$
begin
    insert into beacon_private.game_sessions (owner_id, game_id, name, legacy_owner_id)
    values (new.owner_id, 'b3a00000-0000-4000-8000-000000000001',
        'Beacon session', new.owner_id)
    on conflict (legacy_owner_id) do nothing;
    return new;
end;
$$;
revoke all on function beacon_private.register_beacon_session() from public, anon, authenticated;

drop trigger if exists register_beacon_session on beacon_private.sessions;
create trigger register_beacon_session after insert on beacon_private.sessions
for each row execute function beacon_private.register_beacon_session();

insert into beacon_private.game_sessions (owner_id, game_id, name, legacy_owner_id)
select owner_id, 'b3a00000-0000-4000-8000-000000000001', 'Beacon session', owner_id
from beacon_private.sessions
on conflict (legacy_owner_id) do nothing;

create or replace function public.game_list_published()
returns jsonb language sql stable security definer
set search_path = pg_catalog, beacon_private
as $$
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'title', title, 'description', description, 'engine', engine)
        order by title, id), '[]'::jsonb)
    from beacon_private.games where published;
$$;

create or replace function public.game_list_my_sessions()
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, beacon_private
as $$
begin
    if auth.uid() is null then raise exception 'Warden login required' using errcode = '42501'; end if;
    return coalesce((select jsonb_agg(jsonb_build_object(
        'id', s.id, 'game_id', s.game_id, 'game_title', g.title, 'name', s.name,
        'engine', g.engine, 'created_at', s.created_at)
        order by s.created_at, s.id)
        from beacon_private.game_sessions s
        join beacon_private.games g on g.id = s.game_id
        where s.owner_id = auth.uid()), '[]'::jsonb);
end;
$$;

-- Draft packages are private, immutable snapshots. A draft is not a published game.
create or replace function public.game_save_draft(p_game_id uuid, p_version_id uuid, p_expected_version integer, p_package jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, beacon_private
as $$
declare
    game_row beacon_private.games%rowtype;
    existing beacon_private.game_versions%rowtype;
    current_version integer;
    draft_title text;
    draft_description text;
begin
    if auth.uid() is null then raise exception 'Warden login required' using errcode = '42501'; end if;
    if p_game_id is null or p_version_id is null or p_expected_version is null or p_expected_version < 0
        or p_package is null or jsonb_typeof(p_package) is distinct from 'object'
        or octet_length(p_package::text) > 1048576
        or jsonb_typeof(p_package -> 'catalog') is distinct from 'object'
        or jsonb_typeof(p_package #> '{catalog,title}') is distinct from 'string'
        or jsonb_typeof(p_package #> '{catalog,description}') is distinct from 'string'
        or jsonb_typeof(p_package -> 'definition') is distinct from 'object'
        or p_package #>> '{definition,format}' is distinct from 'vad-scenario'
        or p_package #> '{definition,version}' is distinct from '1'::jsonb
        or jsonb_typeof(p_package #> '{definition,initialState}') is distinct from 'object'
        or jsonb_typeof(p_package #> '{definition,nodes}') is distinct from 'array'
        or jsonb_array_length(p_package #> '{definition,nodes}') = 0 then
        raise exception 'Invalid scenario package' using errcode = '22023';
    end if;
    draft_title := btrim(p_package #>> '{catalog,title}');
    draft_description := p_package #>> '{catalog,description}';
    if length(draft_title) not between 1 and 120 or length(draft_description) > 2000 then
        raise exception 'Invalid catalog title or description' using errcode = '22023';
    end if;

    insert into beacon_private.games (id, owner_id, title, description, engine)
    values (p_game_id, auth.uid(), draft_title, draft_description, 'scenario')
    on conflict (id) do nothing;
    select * into game_row from beacon_private.games where id = p_game_id for update;
    if game_row.owner_id is distinct from auth.uid() or game_row.engine <> 'scenario' or game_row.published then
        raise exception 'Private draft not found or unavailable' using errcode = '42501';
    end if;
    select * into existing from beacon_private.game_versions where id = p_version_id;
    if found then
        if existing.game_id is distinct from p_game_id or existing.version <> p_expected_version + 1
            or existing.definition is distinct from p_package then
            raise exception 'Version identifier already used' using errcode = '22023';
        end if;
        return jsonb_build_object('game_id', p_game_id, 'version_id', p_version_id, 'version', existing.version);
    end if;
    select coalesce(max(version), 0) into current_version from beacon_private.game_versions where game_id = p_game_id;
    if current_version <> p_expected_version then
        raise exception 'Draft changed in another tab; reload before saving' using errcode = '40001';
    end if;
    insert into beacon_private.game_versions (id, game_id, version, definition)
    values (p_version_id, p_game_id, current_version + 1, p_package);
    update beacon_private.games set title = draft_title, description = draft_description where id = p_game_id;
    return jsonb_build_object('game_id', p_game_id, 'version_id', p_version_id, 'version', current_version + 1);
end;
$$;

create or replace function public.game_list_my_drafts()
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, beacon_private
as $$
begin
    if auth.uid() is null then raise exception 'Warden login required' using errcode = '42501'; end if;
    return coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'title', g.title,
        'description', g.description, 'version', v.version, 'version_id', v.id)
        order by g.title, g.id)
        from beacon_private.games g
        join lateral (select id, version from beacon_private.game_versions
            where game_id = g.id order by version desc limit 1) v on true
        where g.owner_id = auth.uid() and g.engine = 'scenario' and not g.published), '[]'::jsonb);
end;
$$;

create or replace function public.game_read_draft(p_game_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, beacon_private
as $$
declare result jsonb;
begin
    if auth.uid() is null then raise exception 'Warden login required' using errcode = '42501'; end if;
    select jsonb_build_object('game_id', g.id, 'version_id', v.id, 'version', v.version, 'package', v.definition)
    into result from beacon_private.games g
    join lateral (select id, version, definition from beacon_private.game_versions
        where game_id = g.id order by version desc limit 1) v on true
    where g.id = p_game_id and g.owner_id = auth.uid() and g.engine = 'scenario' and not g.published;
    if result is null then raise exception 'Private draft not found' using errcode = '42501'; end if;
    return result;
end;
$$;

revoke all on function public.game_list_published() from public;
revoke all on function public.game_list_my_sessions() from public, anon;
revoke all on function public.game_save_draft(uuid, uuid, integer, jsonb) from public, anon;
revoke all on function public.game_list_my_drafts() from public, anon;
revoke all on function public.game_read_draft(uuid) from public, anon;
grant execute on function public.game_list_published() to anon, authenticated;
grant execute on function public.game_list_my_sessions() to authenticated;
grant execute on function public.game_save_draft(uuid, uuid, integer, jsonb) to authenticated;
grant execute on function public.game_list_my_drafts() to authenticated;
grant execute on function public.game_read_draft(uuid) to authenticated;

commit;
