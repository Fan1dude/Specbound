-- Migration: 0023_retailers_and_retail_variants
-- Milestone: 19 — Structured Parts Catalog & Import Architecture
-- Status: PROPOSED — not yet applied. Depends on 0020 (public.components).
--
-- Full design: docs/milestones/MILESTONE_19_PARTS_CATALOG_ARCHITECTURE.md §4.6.
--
-- Purpose: schema-only groundwork for affiliate-ready retailer links, per
-- explicit direction NOT to implement any real affiliate provider
-- integration in this migration — no provider/network column, no
-- affiliate tag, no real retailer data. The goal is that a future
-- affiliate pass can populate and read these tables without a schema
-- redesign, not that it does anything yet.
--
--   Three tables, not two, unlike this migration's first draft
--   (components-and-links directly). components (0020) stays at the
--   granularity builders actually type/search — "NVIDIA GeForce RTX
--   4080" — which is a generic family, not one specific buyable SKU.
--   component_retail_variants sits between a component and its links,
--   representing one specific purchasable product ("ASUS TUF Gaming
--   RTX 4080 OC 16GB"). component_retailer_links attaches to a variant,
--   not to a component directly, because a single generic part is
--   legitimately sold as many different variants across many retailers
--   — collapsing that onto one link-per-component would either force a
--   single "the" URL that doesn't represent the real market, or require
--   a schema change later to add the concept this migration adds now.
--
--   A build's specification value carries a componentId (resolving to
--   the generic family); a future buy-links UI would join through to
--   every variant under that component and show each one's retailer
--   links. A component with zero variants (the default state this
--   milestone leaves everything in) simply has no buy links to show —
--   not an error state, not a dead end.
--
--   Shape takes inspiration from the existing resources jsonb array
--   ({url, label}[]) already used on project_drafts/builds/build_revisions
--   (see 0001, 0005) — this migration formalizes the equivalent as real
--   tables instead, since retailer links need to be queried per-variant
--   across builds, not just listed for one project.
--
--   No affiliate_tag/provider/price column yet — deliberately the
--   minimum shape needed to render a plain outbound link (url + label +
--   which retailer + display order) without a redesign later to add
--   pricing or provider-specific fields.
--
--   Write access: none of the three tables has an insert/update/delete
--   policy for anyone in this migration. All three are intentionally
--   inert until a future phase defines who/what actually populates them
--   (a curated moderator flow extending catalog_moderators, a
--   service-role seeding process, or a real affiliate provider
--   integration) — this is deliberate, not an oversight, per the
--   explicit "schema only, no providers implemented" instruction.
--
--   SQL/security audit pass (2026-07-31): added non-empty checks on
--   name/slug/homepage_url/variant_name/url, a nonnegative check on
--   display_order, and two uniqueness constraints this migration's first
--   draft was missing entirely — unique(component_id, variant_name) on
--   component_retail_variants and unique(variant_id, url) on
--   component_retailer_links. See
--   docs/milestones/MILESTONE_19_SQL_SECURITY_AUDIT.md for the full audit.
--
-- Touches: none (three new tables only). Adds retailers,
-- component_retail_variants, component_retailer_links.
--
-- Rollback: see 0023_retailers_and_retail_variants_rollback.sql in this folder.

begin;

create table public.retailers (
    id uuid primary key default gen_random_uuid(),
    name text not null
        check (char_length(trim(name)) > 0),
    slug text not null unique
        check (char_length(trim(slug)) > 0),
    homepage_url text not null
        check (char_length(trim(homepage_url)) > 0),
    logo_url text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create trigger set_retailers_updated_at
    before update on public.retailers
    for each row
    execute function public.set_updated_at();

create table public.component_retail_variants (
    id uuid primary key default gen_random_uuid(),
    component_id uuid not null references public.components(id) on delete cascade,
    variant_name text not null
        check (char_length(trim(variant_name)) > 0),
    retailer_sku text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    -- Prevents the same literal variant from being added twice under one
    -- component. Case-sensitive, unlike components/component_aliases'
    -- punctuation-insensitive normalization — this table is meant to be
    -- populated by a curated process (moderator tooling or a service-role
    -- seed script, per this file's header comment), not free-text end
    -- users, so the stricter/simpler literal-uniqueness bar is enough.
    constraint component_retail_variants_component_variant_name_key
        unique (component_id, variant_name)
);

create index component_retail_variants_component_id_idx
    on public.component_retail_variants (component_id);

create trigger set_component_retail_variants_updated_at
    before update on public.component_retail_variants
    for each row
    execute function public.set_updated_at();

create table public.component_retailer_links (
    id uuid primary key default gen_random_uuid(),
    variant_id uuid not null references public.component_retail_variants(id) on delete cascade,
    retailer_id uuid not null references public.retailers(id) on delete cascade,
    url text not null
        check (char_length(trim(url)) > 0),
    label text,
    display_order integer not null default 0
        check (display_order >= 0),
    created_at timestamptz not null default now(),

    -- Prevents the exact same URL being attached twice under one variant
    -- (e.g. a retry/double-submit in whatever future process populates
    -- this table). Doesn't prevent two *different* URLs at the same
    -- retailer for one variant — a real possibility (regional storefronts,
    -- bundle listings) that a stricter (variant_id, retailer_id) unique
    -- constraint would have wrongly forbidden.
    constraint component_retailer_links_variant_url_key
        unique (variant_id, url)
);

create index component_retailer_links_variant_id_idx
    on public.component_retailer_links (variant_id, display_order);

alter table public.retailers enable row level security;
alter table public.component_retail_variants enable row level security;
alter table public.component_retailer_links enable row level security;

-- All three readable by everyone, same as the components catalog itself
-- — this is public product/retailer information, not user data.
create policy "Retailers are readable by everyone" on public.retailers
    for select using (true);

create policy "Component retail variants are readable by everyone" on public.component_retail_variants
    for select using (true);

create policy "Component retailer links are readable by everyone" on public.component_retailer_links
    for select using (true);

-- No insert/update/delete policy on any of the three — see header
-- comment. With RLS enabled and no matching policy, all client writes
-- are denied outright until a future migration adds one.

commit;
