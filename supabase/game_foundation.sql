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

revoke all on function public.game_list_published() from public;
revoke all on function public.game_list_my_sessions() from public, anon;
grant execute on function public.game_list_published() to anon, authenticated;
grant execute on function public.game_list_my_sessions() to authenticated;

commit;
