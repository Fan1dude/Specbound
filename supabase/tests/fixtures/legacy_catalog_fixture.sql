-- Production-shaped legacy catalog fixture —
-- supabase/tests/fixtures/legacy_catalog_fixture.sql
--
-- Hand-builds public.components/public.component_aliases in the EXACT
-- shape reported for Specbound's real production catalog (column list,
-- row counts) — used by the legacy-upgrade migration test to prove
-- 0020-0032 safely upgrade a database that already has this data,
-- without ever touching the real production project. Must be applied
-- to a database that already has 0000-0019 (and only 0000-0019)
-- applied — run BEFORE `supabase migration up`, never after.
--
-- Two things below are explicitly fabricated stand-ins, not copies of
-- real production objects, because their exact definitions cannot be
-- read from outside a database connection this project doesn't have:
--   1. Production's real unique constraint/index DDL on these tables —
--      the checkpoint only confirms they exist, not their literal
--      definition. components_legacy_unique_key /
--      component_aliases_legacy_alias_key_key are plausible stand-ins
--      sufficient to prove 0020/0021 coexist with a legacy table that
--      already has its OWN constraint under a different name.
--   2. The body of the live search_components(text,text,text,integer)
--      RPC — confirmed to have no migration file anywhere in this
--      repo. This stand-in has the same signature; the test only
--      proves 0020 never drops/redefines whatever already owns that
--      name, not that this exact body matches production's real one.
--
-- The 9 components / 6 aliases below all satisfy the same properties
-- the compatibility audit reported for real production data:
-- canonical_key/alias_key already match the proposed normalization, no
-- blanks, no normalization collisions, no orphans, no cross-table
-- conflicts between an alias and another component's canonical name.
--
-- Deliberately plain SQL only — no psql meta-commands (\i, \echo,
-- \set) — so this runs the same way through any client. Wrapped in its
-- own begin/commit (not begin/rollback): this must actually persist,
-- since 0020-0032 are applied in a separate step afterward and need to
-- see this data.

begin;

create table public.components (
    id uuid primary key default gen_random_uuid(),
    technology_id text not null,
    component_type text not null,
    canonical_name text not null,
    manufacturer text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    canonical_key text not null
);

alter table public.components
    add constraint components_legacy_unique_key unique (technology_id, component_type, canonical_key);
create index components_legacy_canonical_key_idx on public.components (canonical_key);

alter table public.components enable row level security;
create policy "components_legacy_public_read" on public.components for select using (true);

create table public.component_aliases (
    id uuid primary key default gen_random_uuid(),
    component_id uuid not null references public.components(id) on delete cascade,
    alias text not null,
    created_at timestamptz not null default now(),
    alias_key text not null
);

alter table public.component_aliases
    add constraint component_aliases_legacy_alias_key_key unique (alias_key);

alter table public.component_aliases enable row level security;
create policy "component_aliases_legacy_public_read" on public.component_aliases for select using (true);

-- Stand-in for the live legacy RPC — see header. Signature matches
-- exactly (text, text, text, integer).
create function public.search_components(
    p_technology_id text,
    p_component_type text,
    p_query text default null,
    p_limit integer default 10
)
returns setof public.components
language sql
stable
as $$
    select *
    from public.components
    where technology_id = p_technology_id
      and component_type = p_component_type
      and (
          p_query is null
          or canonical_key like '%' || regexp_replace(lower(p_query), '[^a-z0-9]', '', 'g') || '%'
      )
    order by canonical_name
    limit p_limit;
$$;

-- 9 components, matching the checkpoint's reported row count.
insert into public.components (id, technology_id, component_type, canonical_name, manufacturer, canonical_key) values
    ('10000000-0000-0000-0000-000000000001', 'pc_build', 'cpu',          'AMD Ryzen 7 7800X3D',   'AMD',      'amdryzen77800x3d'),
    ('10000000-0000-0000-0000-000000000002', 'pc_build', 'gpu',          'NVIDIA RTX 4090',       'NVIDIA',   'nvidiartx4090'),
    ('10000000-0000-0000-0000-000000000003', 'pc_build', 'ram',          'Corsair Vengeance 32GB','Corsair',  'corsairvengeance32gb'),
    ('10000000-0000-0000-0000-000000000004', 'pc_build', 'psu',          'Corsair RM850x',        'Corsair',  'corsairrm850x'),
    ('10000000-0000-0000-0000-000000000005', 'pc_build', 'motherboard',  'ASUS ROG Strix B650-A', 'ASUS',     'asusrogstrixb650a'),
    ('10000000-0000-0000-0000-000000000006', 'pc_build', 'storage',      'Samsung 990 Pro 2TB',   'Samsung',  'samsung990pro2tb'),
    ('10000000-0000-0000-0000-000000000007', 'pc_build', 'case',         'Lian Li O11 Dynamic',   'Lian Li',  'lianlio11dynamic'),
    ('10000000-0000-0000-0000-000000000008', 'pc_build', 'cooler',       'Noctua NH-D15',         'Noctua',   'noctuanhd15'),
    ('10000000-0000-0000-0000-000000000009', 'arduino',  'board',        'Arduino Uno R3',        'Arduino',  'arduinounor3');

-- 6 aliases, matching the checkpoint's reported row count.
insert into public.component_aliases (id, component_id, alias, alias_key) values
    ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '7800X3D',        '7800x3d'),
    ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Ryzen 7800X3D',  'ryzen7800x3d'),
    ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', 'RTX 4090',       'rtx4090'),
    ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000002', '4090',           '4090'),
    ('20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000006', '990 Pro',        '990pro'),
    ('20000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000009', 'Uno R3',         'unor3');

-- Snapshot the pre-migration state — permanent tables (NOT temp: the
-- legacy-upgrade assertions run in a separate psql invocation/
-- connection afterward, after `supabase migration up`, and a temp
-- table would not survive across that connection boundary). Dropped by
-- the assertions file once it's done comparing against them.
create table public._legacy_upgrade_pre_components as
    select id, technology_id, component_type, canonical_name, manufacturer, canonical_key from public.components;
create table public._legacy_upgrade_pre_aliases as
    select id, component_id, alias, alias_key from public.component_aliases;

commit;
