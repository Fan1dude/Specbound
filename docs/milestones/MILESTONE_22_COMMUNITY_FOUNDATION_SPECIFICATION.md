# Milestone 22: Community Foundation — Specification

Status: **Approved for implementation, 2026-08-04**, following a final design review (§0). Implementation proceeds on the current branch, in the small, separately-tested commits §13 lays out. No migration is applied to any database beyond a dev project, and nothing is pushed, merged, or applied to production, until the complete milestone is reviewed.

Objective: *"A builder should feel like they belong to a community, not just use a website."*

This milestone is not about adding a lot of features. It's about designing the long-term community architecture so Version 1.0 can ship something small, correct, and extensible — instead of either bolting on Discord/roles/moderation as one-off hacks now, or building a full community platform before it's earned.

---

## 0. Final Design Review — 2026-08-04

Two questions, asked explicitly before implementation: does the public profile need a generalized Social Links system instead of a Discord-only field, and does every new table survive one more round of "can this be merged or derived away?" Both changed something; neither changed the table count.

### 0.1 Discord-only display, or a generalized Social Links system?

**Decided: generalize the storage shape now; do not build multi-provider UI/OAuth now.** What would otherwise be a Discord-specific `discord_accounts` table becomes **`social_connections`** — a `provider text not null check (provider in ('discord'))` discriminator column, `unique (user_id, provider)` instead of `user_id` as the sole primary key, and provider-neutral column names (`provider_user_id`, `provider_username`, `provider_avatar_url` instead of `discord_user_id`/etc.). §4 below is written against this shape directly, not against a Discord-specific design.

Why this is the right line to draw, and not further: the request names LinkedIn/Twitch/Bluesky as plausible future providers, which makes "will another provider be added" a near-certain future, not a hypothetical — exactly the case where a table rename/migration later would otherwise be forced. But an OAuth-verified connection and a plain-text profile URL are genuinely different things, not two cases of one "social link" concept:

- `profiles.github` / `profiles.website` / `profiles.youtube` are unverified free text — a builder can type anything. They already work, they're outside this milestone's scope, and **this review does not propose folding them into `social_connections`** — doing so would mean either fabricating a fake "verified" state for links that were never OAuth-checked, or adding a `verified boolean` that's always false for three of four rows, neither of which simplifies anything. Touching those three columns is a Builder Portfolio data-model change with no request behind it, and is explicitly not made here.
- A second real OAuth provider (say, Twitch) needs its own Supabase Auth provider configuration, its own consent-scope decisions, and its own UI entry point — none of that is speculative-proofed by a table rename, and none of it is built here. Building a plugin-style multi-provider OAuth system now, for providers nobody has asked to connect yet, is exactly the "unnecessary complexity" the instruction warns against.

So the shape is generic (adding a provider later is a `CHECK` constraint edit plus application code, not a migration that moves data), but the actual V1 surface is unchanged: one provider, one small addition to the existing hero link row (§4.8), nothing new visually. This is the cheapest possible hedge against a near-certain future, stopped exactly at the point where it would start costing something real.

### 0.2 Every table, challenged again

| Table | Could it be derived from existing data? | Could it merge into another table without making the design worse? | Verdict |
|---|---|---|---|
| `social_connections` (was `discord_accounts`) | No — external identity, nothing to derive it from. | Considered merging into `profiles` directly (a few extra columns). Rejected: bloats the row fetched on every profile view for a feature most rows won't use yet, and can't express "more than one provider" without becoming this table anyway. | Keep, generalized (§0.1). |
| `profile_roles` | No — manually-awarded and permission roles are human decisions by construction (§5.2); that's the anti-gamification point, not a gap to fill with a formula. | Considered collapsing into a `profiles.role` column. Rejected: a builder can hold more than one role at once (a Moderator who's also a recognized Project Mentor) — a single column can't express that without becoming an array and losing `granted_by`/`granted_at`/`note` per grant. | Keep. |
| `content_reports` | No — nothing today lets any user flag anything. | Re-examined merging into `moderation_actions` one more time, concretely rather than in the abstract: a merged table would need conditional/nullable columns for "who reported vs. who acted," the anti-duplicate `unique (reporter_id, target_type, target_id)` constraint would need a partial index scoped to one action type, and the moderator queue's "all currently-open reports" query would become a self-join instead of `WHERE status = 'open'`. Every one of those is a concrete regression, not just a stylistic preference — merging makes this table *worse* by the instruction's own test. | Keep, separate from `moderation_actions`. |
| `moderation_actions` | No — an audit trail of actions taken has no other source. | See above — kept separate from `content_reports` for the same concrete reasons, not merely to avoid a merge. | Keep. |
| `feedback_submissions` | No — freeform product feedback, nothing to derive. | Considered merging into `content_reports` (both are "a user flags something"). Rejected: a report always targets a specific build/comment/profile; feedback never does — `target_type`/`target_id` would be null on every feedback row, an awkward fit for a NOT NULL pair that exists specifically to identify a target. | Keep, separate. |
| `beta_invites` | **Partially** — see below. | N/A, structurally unique (a redeemable code with usage counting). | Keep, narrowed. |

**The one genuine simplification this pass found**: §10's "manual invitations" doesn't need `beta_invites` at all. Supabase Auth already has a native admin invite-by-email feature (`supabase.auth.admin.inviteUserByEmail()`), callable only with the service-role key — which lives in the Supabase dashboard, never in this app's client code, the same operational posture already established for applying migrations and (per §5.3) minting the first Staff account. Inviting a specific, already-known person by email needs zero new schema or application code — it's a dashboard action. What `beta_invites` is actually for, and the only thing it's kept for, is the *other* half of §10: a **shareable code** (posted in Discord, handed to a friend) redeemable by someone whose email isn't known in advance — a capability Supabase's built-in invite genuinely cannot provide, since it requires the recipient's email up front. §10 below is corrected to say this explicitly instead of implying the table covers both cases.

**Net result: still six new tables, one new column, one widened constraint** — the same count as the original spec, because nothing here found actual redundancy to remove, only two places where the *shape* or *claimed scope* of a table was wrong. Per the instruction ("if you find a simplification, prefer it") — both simplifications found are applied below; no further table was collapsible without a concrete loss.

---

## 1. Relationship to Governing Docs — read this first

Three documents in this repo are marked **Authoritative, Approved 2026-07-28**: `docs/SCOPE.md`, `docs/PRODUCT_ARCHITECTURE.md`, `docs/PRODUCT_PRINCIPLES.md`. All three currently say things this milestone directly contradicts on their face:

- `SCOPE.md`'s Explicitly Out of Scope list includes **"gamification"**.
- `PRODUCT_ARCHITECTURE.md` §5 (Feedback & Connection System) explicitly lists **"Discord integration"** among features "explicitly not approved for V1."
- `docs/PARKING_LOT.md` still marks "Achievements" as parked, "gamification," not promoted.

At the same time, `docs/BETA_LAUNCH_CHECKLIST.md` (present in this working tree, not yet committed) already lists **Discord Integration**, **Moderation**, an **Invite page**, a **Feedback form**, and **"Discord ready"** as open beta-launch checklist items — meaning this direction is already the intended next step, just not yet reconciled with the three "authoritative" docs above.

This spec resolves that tension the same way `PRODUCT_ARCHITECTURE.md`'s own history note resolves an earlier version of itself (it says outright that it supersedes a prior draft that "framed... a Discord-integrated Community/Forums system as near-term" and that framing was deliberately walked back once). The resolution here is **not** "add a social platform" — it's the opposite: everything in this spec is designed to satisfy `PRODUCT_PRINCIPLES.md`'s own belief system (*"Reward popularity over quality" and "Exist only because other social platforms have them" are both on the avoid-list*) while still shipping Discord/roles/moderation/feedback/beta-invites as real, narrow, non-gamified features.

**Recommended edits, for approval alongside this spec** (not made yet):
- `SCOPE.md`: add under Community Features — Approved for V1: *"Discord account linking (identity + optional display only — no server bot, no XP)"*, *"Non-competitive recognition roles (no points, no leaderboard)"*, *"Content reporting to moderators"*, *"Lightweight in-app feedback"*. Leave "gamification," "XP or levels," "engagement-based achievements," "streaks" exactly as-is — this milestone doesn't touch any of them.
- `PRODUCT_ARCHITECTURE.md` §5: replace the single line "Discord integration" in the not-approved list with a pointer to this document, since it's now scoped and approved in this narrower form.

Every feature below is checked against the instruction's own test — *does this help builders build, document, or learn from each other?* — and against `PRODUCT_PRINCIPLES.md`'s avoid-list. Where something fails either test, it's named explicitly as **out of scope**, not quietly dropped.

---

## 2. Current-State Findings

Grounding facts, confirmed by reading the actual code and schema, not assumed:

- **No Discord code exists anywhere in this repo.** Confirmed by a full-repo search — every hit is a doc mention (`BETA_LAUNCH_CHECKLIST.md`, architecture docs). This is a from-scratch design, not an integration with something partial.
- **No role/permission concept exists except one, narrowly scoped.** `catalog_moderators` + `is_catalog_moderator()` (Milestone 19, `0020_components_catalog.sql`) is, in that migration's own words, *"the first admin-role concept in this app, deliberately scoped to this one subsystem (not a general 'is_admin' flag)."* This is the direct precedent §6 builds on — same shape (a grants table + a `SECURITY DEFINER` boolean-check function), applied to a new subsystem, not generalized into a sitewide `is_admin`.
- **No moderation, reporting, or audit-log mechanism exists at all.** Confirmed by search — `component_submissions`' moderator-review flow (Milestone 19) is the closest precedent for an approve/reject RPC pattern, but it moderates catalog entries, not user content or user reports.
- **No feedback mechanism exists.** The "Feedback" text in `design-system.html` is a generic section-eyebrow label on the design-system showcase page, unrelated to an actual feedback system.
- **No invite/beta-gating mechanism exists.** Confirmed by search.
- **The notification system is a single `notifications` table** (`0011_notifications.sql`) with a `type` `CHECK` constraint (`'comment' | 'like' | 'save' | 'reply'`, `'reply'` reserved-but-unused ahead of a future feature) and a `create_notification()` function that is **not grantable to any client role at all** — it only exists to be called from inside other already-`SECURITY DEFINER` functions. This is the exact pattern §4/§6 reuse for any new notification types.
- **`js/core/supabase.js` uses `@supabase/supabase-js@2.110.8`**, loaded from a CDN, no server/edge-function layer anywhere in this repo (`supabase/functions/` doesn't exist). This is the single most important constraint on the Discord OAuth design in §4 — there is nowhere in this app's architecture to safely hold an OAuth `client_secret` today, and adding a custom backend just for that would be a large, unjustified infrastructure jump for what Supabase Auth already does natively (see §4.1).
- **`pages/legal/community-guidelines.html` already exists as a "Coming Soon" placeholder**, wired into `loadNavbar()`/`loadFooter()` like every other page. §5 designs real content structure for it (not final copy) rather than creating a new page.
- **The Builder Portfolio hero** (`js/pages/profile/renderProfileHero.js`, Milestone 20) already renders `github`/`website`/`youtube` as plain always-shown-if-filled links, with no existing "verified" or "connect" concept — Discord display (§1, §4) is a new, different kind of link (identity-verified, owner-toggleable), not a fourth entry in that same unverified list.
- **Badge styling today is minimal**: `.badge`/`.hero-badge` (neutral pill) and `.badge-outline` are the only reusable classes; `badge-success`/`badge-unpublished` exist but are scoped to `#editorPublishBadge` specifically, not general-purpose. There is no existing color-tiered badge ladder to reuse or avoid — §3's "no visual ranking" decision is a fresh choice, not a fight against existing precedent.
- **Settings (`pages/settings.html`) is one flat profile form** plus a separate password-change form — no "Connected Accounts" section exists yet. This is where §4's Discord connect/disconnect UI is proposed to live.
- **The Workshop readiness-checklist / profile-completion-checklist pattern** (`js/services/draftValidation.js`, Milestone 20; `js/services/profileCompletion.js`, Milestone 21) — pure functions, computed live, no persisted "score" — is the direct model this spec follows for every *automatic* role in §3, and for why no reputation *number* is introduced anywhere in §3's design.

---

## 3. Design Position

Every section below is written against one filter, repeated from the request: **does this help builders build, document, or learn from each other?** Concretely, that means:

- Recognition is **qualitative** (a name, a badge, a small note of thanks), never **quantitative** (no score, no counter, no percentile). `PRODUCT_PRINCIPLES.md`'s "Success is not measured by likes" applies exactly as much to a hypothetical "reputation: 1,240" as it does to a like count.
- Moderation exists to **protect the ability to build and document safely**, not to run a justice system. V1 ships the minimum real primitives (report, review, log) — not a dashboard, not a case-management tool.
- Discord is a **bridge to an identity a builder already has**, not a second product to maintain. V1 links and displays; it does not operate a bot, does not push roles into a Discord server, and does not require Discord to use Specbound.
- Beta is **closed, small, and manually operated** (BETA_LAUNCH_CHECKLIST.md: *"First 25 builders invited"*) — its schema should fit that reality, not a hypothetical open-signup-at-scale future.

---

## 4. Discord Integration (§1 + §4 combined — they're one system)

Per §0.1, the storage shape below is generalized (`social_connections`, `provider`-discriminated) even though Discord is the only provider built in this milestone — everything else in this section is exactly as originally specified.

### 4.1 OAuth architecture — the one decision everything else depends on

**Decided: use Supabase Auth's native identity-linking (`supabase.auth.linkIdentity()`), not a hand-rolled OAuth flow.**

Reasoning: a standard OAuth2 authorization-code exchange requires a `client_secret`, which must never be exposed to client-side JavaScript. This app has no server component anywhere (§2) — building one solely to hold a Discord secret would be a disproportionate new piece of permanent infrastructure (hosting, monitoring, a second deploy target) for what Supabase's own Auth service already does, server-side, as a built-in feature. Supabase Auth already performs exactly this exchange for every `signInWithOAuth` provider; `linkIdentity()` is the same mechanism, scoped to *attaching* a second identity to an already-signed-in user rather than signing in fresh. This keeps the app's zero-backend architecture completely intact.

**Deployment prerequisite (operational, not code):** a Discord Developer Portal application must be created, its OAuth redirect URI registered, and its client ID/secret entered into the Supabase project's Auth → Providers → Discord settings. This is the same category of one-time, dashboard-level setup as the SMTP/SPF/DMARC items already tracked in `BETA_LAUNCH_CHECKLIST.md`'s Infrastructure section — not something any migration or application code can do, and explicitly called out here so it isn't missed at implementation time.

### 4.2 Sequence

```
Builder (Settings page)          Specbound (client JS)          Supabase Auth          Discord
        |                               |                            |                    |
        |-- click "Connect Discord" --->|                            |                    |
        |                               |-- linkIdentity('discord',  |                    |
        |                               |    redirectTo=settings) -->|                    |
        |                               |                            |-- redirect user -->|
        |                               |                            |                    |-- consent screen
        |                               |                            |<-- approve --------|
        |                               |<----- redirect back to Settings, session --------|
        |                               |         (auth.identities now has a Discord row,  |
        |                               |          owned by this user — Supabase-managed)  |
        |                               |-- call sync_discord_identity() RPC ------------->|
        |                               |   (SECURITY DEFINER: reads the caller's own      |
        |                               |    auth.identities row, upserts the public       |
        |                               |    mirror row — see §4.4)                        |
        |<-- "Connected as {username}" -|                            |                    |
```

Discord tokens are **never stored by this application at all** — Supabase Auth holds them internally (in its own `auth` schema, never exposed via PostgREST). This app only ever reads the already-authenticated identity's public claims (Discord user id, username, avatar), never a token. This is a direct, significant simplification from a hand-rolled OAuth design, and worth stating plainly: there is no token refresh, no token encryption, no token expiry to manage in this app's own code, because this app never holds one.

### 4.3 Verifying Discord ownership

Ownership verification is inherent to the OAuth flow itself — Discord's own consent screen is what proves the connecting browser controls that Discord account, exactly the same guarantee email confirmation gives for a Specbound account. No separate "verify" step is needed or proposed; a successful `linkIdentity()` **is** the verification.

### 4.4 Database changes

One new table.

```sql
-- provider is CHECK-constrained to a single value today — per §0.1, this
-- is a shape ready for a second provider, not a system that supports
-- one. Widening the CHECK later is a one-line migration, same pattern as
-- notifications.type's 'reply' reservation; it does not move data.
create table public.social_connections (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    provider text not null check (provider in ('discord')),
    provider_user_id text not null,
    provider_username text not null,
    provider_avatar_url text,
    is_public boolean not null default false,
    connected_at timestamptz not null default now(),
    last_synced_at timestamptz not null default now(),

    -- One connection per (user, provider) — a builder could in principle
    -- hold several provider connections at once, just never several of
    -- the same provider.
    unique (user_id, provider),
    -- One external identity can't back two Specbound accounts on the
    -- same provider — the database-level guarantee, not an application
    -- assumption.
    unique (provider, provider_user_id)
);

alter table public.social_connections enable row level security;

create policy "Users can view their own Discord connection" on public.social_connections
    for select
    to authenticated
    using (auth.uid() = user_id);

-- Public profile pages need to read is_public connections for anyone —
-- separate policy, not "using (true)" on the row generally, so a
-- profile's Discord username is only ever readable by anyone when the
-- owner has explicitly opted in.
create policy "Anyone can view a publicly-shown Discord connection" on public.social_connections
    for select
    using (is_public = true);

-- Deleting your own row is a plain owner-scoped RLS policy (§4.7
-- Disconnect) — no RPC needed for this direction, unlike the insert/
-- update path below, which must read auth.identities (SECURITY DEFINER
-- required; a normal client role cannot read that schema at all).
create policy "Users can disconnect their own Discord account" on public.social_connections
    for delete
    to authenticated
    using (auth.uid() = user_id);

create policy "Users can change their own display visibility" on public.social_connections
    for update
    to authenticated
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
```

**`sync_discord_identity()` — the only way a row is created.** Kept Discord-specific as a *function*, deliberately not parameterized by provider — §0.1's generalization is about the storage shape, not about building multi-provider OAuth handling nobody has asked for yet; a real second provider would get its own `sync_<provider>_identity()` function when it's actually built, sharing the one generic table:

```sql
create or replace function public.sync_discord_identity()
returns public.social_connections
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_identity jsonb;
    v_result public.social_connections;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in.';
    end if;

    -- auth.identities is not exposed to PostgREST/RLS for direct client
    -- reads — SECURITY DEFINER is what lets this function read it at
    -- all, scoped to the caller's own identities only (never anyone
    -- else's, since the WHERE clause is auth.uid() itself, not a
    -- parameter).
    select identity_data into v_identity
    from auth.identities
    where user_id = auth.uid() and provider = 'discord'
    order by last_sign_in_at desc
    limit 1;

    if v_identity is null then
        raise exception 'No linked Discord account found. Connect Discord first.';
    end if;

    insert into public.social_connections (user_id, provider, provider_user_id, provider_username, provider_avatar_url, last_synced_at)
    values (
        auth.uid(),
        'discord',
        v_identity->>'provider_id',
        coalesce(v_identity->>'global_name', v_identity->>'user_name', v_identity->>'full_name'),
        v_identity->>'avatar_url',
        now()
    )
    on conflict (user_id, provider) do update set
        provider_user_id = excluded.provider_user_id,
        provider_username = excluded.provider_username,
        provider_avatar_url = excluded.provider_avatar_url,
        last_synced_at = now()
    returning * into v_result;

    return v_result;
end;
$$;

revoke all on function public.sync_discord_identity() from public;
grant execute on function public.sync_discord_identity() to authenticated;
```

The exact JSON key names in `identity_data` (`global_name` vs. `user_name` vs. Discord's legacy `username#discriminator` shape) depend on what Supabase's Discord provider actually populates — not verifiable from this environment (no live Supabase project access). Flagged for a smoke-test at implementation time against a real linked account, same category of caveat as Milestone 20's `builds!inner` embedded-filter note — the fallback chain (`global_name` → `user_name` → `full_name`) is a defensive guess, not confirmed.

### 4.5 Synchronization strategy

**Pull only, manual re-sync, no background job.** The client calls `sync_discord_identity()`:
1. Once, automatically, right after a successful `linkIdentity()` redirect back to Settings (§4.2).
2. On demand, via a "Refresh" button next to the connected-account display in Settings — the same idempotent `on conflict do update` call, updating `last_synced_at`. This is the entire re-sync process; there is no separate re-sync mechanism to design.

No scheduled/cron sync is proposed for V1 — a Discord username changing is low-stakes and low-frequency; a manual refresh button is proportionate. A future background sync (e.g., nightly) is a one-line addition once real usage shows it's needed, not designed further here.

### 4.6 Failure handling

| Failure | Where it surfaces | Handling |
|---|---|---|
| User denies consent on Discord's screen | Redirect back to Settings with an error state Supabase's SDK exposes | Toast: "Discord connection cancelled." No row created, no partial state. |
| Discord account already linked to a different Specbound account | `linkIdentity()` itself rejects (the provider+provider-id pairing is unique at the Supabase Auth level) | Toast: "This Discord account is already connected to another Specbound account." |
| `linkIdentity()` succeeds but `sync_discord_identity()` fails (network drop, etc.) | Settings page | Self-healing: Settings' load path checks `getUserIdentities()` for a Discord identity; if one exists but no local `social_connections` row does (or `last_synced_at` looks stale), it silently retries the sync call once. Matches the fail-open, self-healing posture already established in Milestone 21 (e.g. the readiness-checklist reload-timing fix). |
| `sync_discord_identity()` called with no linked identity at all | Any direct call, defensively | Raises a clear error (`'No linked Discord account found...'`) — should be unreachable from the real UI (the Refresh/initial-sync buttons only render once a linked identity is confirmed to exist), but the RPC itself doesn't trust the client to have checked. |

### 4.7 Disconnect flow

1. Settings → "Disconnect" button next to the connected account.
2. `confirmDialog()` (existing shared component, reused verbatim) — *"Disconnect Discord? Your Discord connection and any public display of it will be removed."*
3. On confirm: `supabase.auth.unlinkIdentity(identity)` (removes the Supabase-level link — the object comes from `getUserIdentities()`), then delete the `public.social_connections` row via the plain owner-scoped RLS delete policy (§4.4) — no RPC needed for this direction.
4. UI reverts to the "Connect Discord" empty state.

If `unlinkIdentity()` succeeds but the local delete fails (or vice versa), the same self-healing check from §4.6 applies in reverse: Settings' load path treats "no linked identity, but a `social_connections` row still exists" as a stale-row case and deletes it client-side on next load.

### 4.8 Display on Builder Profile

Optional, owner-controlled, via `social_connections.is_public` (§4.4) — connecting Discord (for future role-sync / verification purposes) never implies public display; those are two separate decisions, unlike the existing `github`/`website`/`youtube` fields, which have no connect/display distinction because they're plain unverified text, not an OAuth-backed identity. When `is_public = true`, the Discord username renders in the same hero meta row as the existing external links (`renderProfileHero.js`) — one more small icon+text item in an already-established list pattern, **not** a new section or layout change. This is the one place this spec touches Builder Portfolio's actual markup, and it's flagged explicitly in §12 as needing separate sign-off, consistent with the "do not redesign Builder Portfolio" constraint — this is an additive list item, not a restructuring.

### 4.9 Discord nickname sync — explicit recommendation

The request asks for this "if appropriate." Broken into its two possible directions:

- **Pulling** the Discord username for read-only display (§4.4, §4.8): appropriate, zero new infrastructure, already fully specified above.
- **Pushing** a Specbound username into a Discord server as that member's nickname: **not appropriate for V1.** It requires a Discord bot application with `MANAGE_NICKNAMES` permission in a specific target guild, a decision about *which* guild is "the" Specbound server, and (per Discord's own platform norms) very explicit separate consent before an app renames someone's identity inside a community they don't otherwise control. None of that infrastructure exists, and building it is a materially bigger scope item than "connect an account." Recorded here as a **named future item**, not designed further: it would need its own bot credential, its own scoped architecture doc, and explicit approval before any code — the `social_connections` schema above doesn't block it (a future `guild_id`/`nickname_synced_at` column would be additive), but nothing here implements it.

### 4.10 Future-proofing

- **Role sync into Discord** (§5): deferred to the same future bot-infrastructure item as §4.9 — the `profile_roles` table (§5, §9) is already shaped so a future sync job can read "which roles does this user have" without any schema change; it just has nothing to push to yet.
- **Multiple guilds**: out of scope — `social_connections` is one row per Specbound user, not scoped to a guild, because V1 has no guild-specific behavior at all (no bot, no role push). If guild-scoped behavior is ever built, it's a new table referencing this one, not a rework of it.

---

## 5. Community Roles

**Decided: one system, `profile_roles`, spanning both automatic-computed recognition and manually-granted permission roles** — see §9 for why these were merged into one table rather than kept as parallel systems, once it became clear a permission role (Moderator) is really just a recognition role with an attached capability, not a structurally different kind of thing.

| Role | Automatic or manual | Carries a permission? | Syncs to Discord | Website-only? |
|---|---|---|---|---|
| New Builder | **Automatic** — computed, not stored | No | No (too transient/low-value to sync) | Yes |
| Active Builder | **Automatic** — computed, not stored | No | No | Yes |
| Long-Term Builder | **Automatic** — computed, not stored | No | Future (stable tenure signal) | Yes, for V1 |
| Community Builder | **Manual** — staff/moderator-awarded | No | Future | Yes, for V1 |
| Project Mentor | **Manual** — staff/moderator-awarded, builder-eligible opt-in | No | Future | Yes, for V1 |
| Moderator | **Manual** — staff-granted only | **Yes** — §6 permissions | Future (bot required, §4.9) | Yes, for V1 |
| Staff | **Manual** — highest trust, granted outside the app (see §5.3) | **Yes** — §6 permissions, plus granting Moderator | Future | Yes, for V1 |

No role in this milestone syncs into Discord in V1 — every "Future" above depends on the same bot infrastructure explicitly deferred in §4.9. The schema doesn't block it later; nothing pushes anything now.

### 5.1 Automatic roles — computed, not stored

Exactly the same shape as Milestone 21's `getProfileCompletionChecks()` — a pure function over data that already exists, re-evaluated on every render, no new column:

```js
// js/services/communityRecognition.js (proposed, not built)
export function getAutomaticRole(profile, builds) {
    const accountAgeMonths = monthsSince(profile.created_at);
    const hasRecentActivity = builds.some(b => monthsSince(b.updated_at) < 1);

    if (accountAgeMonths >= 6 && hasRecentActivity) return "long_term_builder";
    if (hasRecentActivity) return "active_builder";
    return "new_builder";
}
```

A builder has exactly one automatic role at a time (a simple, honest, evolving status — not a badge collection). No table row, no history — recomputed fresh every time, exactly like the profile checklist.

### 5.2 Manually-awarded roles

`Community Builder` and `Project Mentor` are awarded by a Moderator or Staff member through a direct action (§9's `profile_roles` insert, via an RPC gated by `is_platform_moderator()`) — not computed from any formula. This is the deliberate anti-gamification choice: there is no comment-count or helpfulness-score threshold that auto-grants these, because a formula is exactly the kind of "engagement farming" surface `PRODUCT_PRINCIPLES.md` and the request both explicitly reject. A human decides, the same way `builds.featured` is a human curatorial decision, not an algorithm.

### 5.3 Moderator and Staff

Both are permission-bearing, both manually granted via `profile_roles` (§9). Staff is the higher trust tier — for V1, **granting the very first Staff account is an out-of-band, direct-database operation** (the same "operated via Supabase SQL editor" posture already used for applying migrations themselves throughout this project's workflow), not a self-service flow — there is no bootstrapping problem to solve in-app for a closed beta of 25 people. Once at least one Staff account exists, Staff can grant Moderator (and additional Staff) through the app (§6).

### 5.4 What roles are explicitly not

No role has a numeric level, no role expires on a timer, no role is lost for inactivity, no role is visible as a ranked list anywhere (no "top builders" page). A role badge answers "what is this person's relationship to the community," never "how much has this person done compared to others."

---

## 6. Reputation Philosophy

There is no reputation *number* anywhere in this milestone — no column, no score, no percentile, no "reputation: N" displayed on any page. "Reputation" in this spec means exactly two things, both already qualitative:

1. **The role badge** (§5) — a small, honest, non-competitive label.
2. **Visible history that already exists** — published project count, comment history, follower relationships (already explicitly "functional, not a leaderboard" per `PRODUCT_ARCHITECTURE.md` §3) — none of it new, none of it aggregated into a single score.

What this rewards, concretely:

| Behavior | How it's recognized |
|---|---|
| Documenting projects | Already visible via the Builder Portfolio's project count/gallery (Milestone 20) — no new mechanic needed, this is the platform's whole point already |
| Helping other builders | `Project Mentor` role (§5.2), awarded by a moderator who's observed it — not measured by a comment-count formula |
| Constructive comments | No automated detection (explicitly avoided — "constructive" is not a metric a query can compute without inviting exactly the gaming this milestone is designed to avoid); surfaced only through the same manual `Community Builder`/`Project Mentor` recognition path |
| Long-term participation | `Long-Term Builder` automatic role (§5.1) — time-based, not activity-scored |

**Explicitly avoided, and why each one fails the request's own test:**
- Leaderboards / "top builders" — ranks people against each other; the opposite of "recognition rather than competition."
- Levels / XP — implies a score existing to be maximized, which is what "engagement farming" means in practice.
- Daily streaks — rewards *showing up*, not *building or documenting*; directly fails "does this help builders build, document, or learn from each other?"
- Engagement-farming counters (view counts as status, like counts as status) — already excluded by `SCOPE.md`'s existing "no likes, no vanity counters" rule; this milestone doesn't reopen that.

---

## 7. Community Guidelines

**Where they live:** the existing placeholder page, `pages/legal/community-guidelines.html` — real content structure replaces the "Coming Soon" body; final copy is explicitly out of scope for this pass, per the request.

**Proposed structure** (headings only, no copy):
1. Why Specbound has guidelines (one short framing paragraph)
2. What's encouraged (documentation quality, constructive feedback, helping newcomers)
3. What's not tolerated (harassment, spam, plagiarized project content, low-effort/engagement-bait posting)
4. How reports work (points to §8's report entry points, sets expectations for response)
5. Enforcement (references §6's moderator role, states action range without inventing a strike-count system here)

**Acceptance:** the request explicitly rules out redesigning onboarding, so acceptance is **not** wired into the Milestone 21 Welcome dialog or checklist. Instead: `profiles.guidelines_accepted_at timestamptz` (nullable, §9), checked lazily at the first moment a builder does something community-facing — **publishing a build** or **posting a comment**, whichever happens first. If null at that moment, a lightweight inline consent (a real `<input type="checkbox">` + link to the guidelines page, blocking only that one action with the same disabled-button-plus-visible-reason pattern already established for the editor's Publish button in Milestone 20/21) is shown once; accepting sets the timestamp and the action proceeds immediately. Nothing about sign-up, the Welcome dialog, or the profile checklist changes.

---

## 8. Moderator Foundation (architecture only)

### 8.1 Roles and permissions

| Capability | Moderator | Staff |
|---|---|---|
| View all content reports (§8.3) | ✓ | ✓ |
| Resolve a report (dismiss / action taken) | ✓ | ✓ |
| Grant `Community Builder` / `Project Mentor` | ✓ | ✓ |
| Grant `Moderator` | — | ✓ |
| Grant `Staff` | — | ✓ (or out-of-band only, §5.3) |
| View the audit log (§8.4) | ✓ (own actions + all, for transparency) | ✓ |

Two `SECURITY DEFINER` helper functions, directly mirroring `is_catalog_moderator()` (Milestone 19):

```sql
create or replace function public.is_platform_moderator(p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, pg_temp
as $$
    select exists (
        select 1 from public.profile_roles
        where user_id = p_user_id and role in ('moderator', 'staff')
    );
$$;

create or replace function public.is_platform_staff(p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public, pg_temp
as $$
    select exists (
        select 1 from public.profile_roles
        where user_id = p_user_id and role = 'staff'
    );
$$;
```

Deliberately **separate** from `is_catalog_moderator()` — not merged, not generalized into one `is_admin()`. Same reasoning Milestone 19 already gave for why catalog moderation is its own narrow thing: a catalog moderator curates parts-catalog data quality; a platform moderator handles community reports and role grants. Someone could reasonably hold one without the other. A future decision to unify them is possible but not assumed here.

### 8.2 Future moderation dashboard — named, not built

A dedicated page (e.g. `pages/moderation.html`, gated by `is_platform_moderator()`) reading `content_reports` + `moderation_actions` + `profile_roles` is the natural next step once report volume justifies it. Not built in this milestone — the three tables in §8.3/§8.4/§9 are shaped so that page has everything it needs the day it's built, without a schema change.

### 8.3 Report entry points

One new table, `content_reports` — the actual new capability this section exists for (nothing today lets a builder report anything).

```sql
create table public.content_reports (
    id uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references auth.users(id) on delete cascade,
    target_type text not null check (target_type in ('build', 'comment', 'profile')),
    target_id uuid not null,
    reason text not null check (char_length(trim(reason)) > 0),
    status text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
    reviewed_by uuid references auth.users(id) on delete set null,
    reviewed_at timestamptz,
    created_at timestamptz not null default now(),

    -- One open report per (reporter, target) — re-reporting the same
    -- thing updates the existing row's reason via the RPC below rather
    -- than piling up duplicates, the same minimal anti-spam shape as
    -- Milestone 19's per-user pending-submission cap.
    unique (reporter_id, target_type, target_id)
);
```

`target_id` is a plain `uuid`, not a foreign key — it can point at `builds`, `comments`, or `profiles`, three different tables, which a single FK column can't express without a partial/polymorphic constraint this schema doesn't need yet. Referential integrity for "does this target still exist" is enforced at read time by the moderation dashboard (§8.2) joining against whichever table `target_type` names, not at write time — reporting something that's since been deleted is a legitimate report (deleted-but-still-actioned-against a user), not an error.

RLS: reporters see their own reports; `is_platform_moderator()` sees all. No direct `UPDATE` policy — resolution goes through an RPC:

```sql
create or replace function public.report_content(
    p_target_type text,
    p_target_id uuid,
    p_reason text
)
returns public.content_reports
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_report public.content_reports;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to report content.';
    end if;

    insert into public.content_reports (reporter_id, target_type, target_id, reason)
    values (auth.uid(), p_target_type, p_target_id, trim(p_reason))
    on conflict (reporter_id, target_type, target_id)
        do update set reason = excluded.reason, status = 'open', reviewed_by = null, reviewed_at = null
    returning * into v_report;

    return v_report;
end;
$$;
```

**Entry points in the UI** (component-level, not new pages): a small "Report" affordance added to the existing comment-item template (`renderComments.js`) and to `BlueprintCard`'s/build-page's overflow area — a real `<button>` opening a tiny reason form (reuses the `confirmDialog()` `<dialog>` construction, not a new modal system), consistent with §12's "reuse existing shared components" constraint. Not built in this pass — named here as exactly where §13's implementation phases would add it.

### 8.4 Audit logging

Second new table — deliberately **separate** from `content_reports` rather than merged into it (see §9 for the explicit trade-off): a report is something a *user* submits before any decision exists; an audit-log entry is something a *moderator* did, which can happen with or without a prior report (e.g., proactively removing something a moderator noticed directly).

```sql
create table public.moderation_actions (
    id uuid primary key default gen_random_uuid(),
    actor_id uuid not null references auth.users(id) on delete cascade,
    action_type text not null check (action_type in (
        'report_resolved', 'role_granted', 'role_revoked', 'content_removed'
    )),
    target_type text not null,
    target_id uuid not null,
    note text,
    created_at timestamptz not null default now()
);
```

RLS: `is_platform_moderator()` can `SELECT`; no client `INSERT` policy at all — every row is written by the same `SECURITY DEFINER` RPCs that perform the underlying action (`resolve_report()`, `grant_profile_role()`), so an audit entry can never be forged or skipped by a client that has moderator access but bypasses the "proper" RPC — there is no other path to the privileged action in the first place.

### 8.5 Explicitly out of scope for this milestone

- Content removal/hiding itself (the `content_removed` action type is reserved in the CHECK constraint the same way `notifications.type`'s `'reply'` was reserved in Milestone 7B — for future compatibility, not because this milestone implements removal).
- Appeals process.
- Automated content scanning/flagging.
- A public "trust and safety" transparency report.

---

## 9. Feedback System

One new table, one small UI entry point, no admin UI yet.

```sql
create table public.feedback_submissions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references auth.users(id) on delete set null,
    category text not null check (category in ('bug', 'confusing', 'suggestion', 'feature_request')),
    message text not null check (char_length(trim(message)) > 0 and char_length(message) <= 2000),
    page_url text,
    status text not null default 'open' check (status in ('open', 'reviewed', 'closed')),
    created_at timestamptz not null default now()
);
```

`user_id` is nullable with `on delete set null` (not `cascade`) — a deliberate choice: feedback is useful product signal that should outlive the account that submitted it (a builder who later deletes their account shouldn't silently delete their bug reports too), unlike every other user-owned row in this schema, which does cascade. `category` is a plain `CHECK`-constrained column, not an enum type or a lookup table — adding a fifth category later is a one-line constraint change, the same low-ceremony extensibility already established for `notifications.type`.

RLS: a signed-in user can insert their own (and view their own submission history, a small transparency courtesy); `is_platform_moderator()` can view all. No update policy for the submitter (a submitted report shouldn't be editable after the fact) — future triage (`status` transitions) goes through a moderator-gated RPC, not built in this pass.

**Entry point:** a persistent "Feedback" link in the existing global footer (`layout.js`'s `loadFooter()`, which already has Platform/Builders/Legal columns — one more link, not a new footer section) opening a small reuse of the `confirmDialog()` `<dialog>` construction with a category radio group and a message textarea. No new page.

---

## 10. Beta Community

One new table — and, per §0.2's review, only for the shareable-code half of this section. **Manual invitations** (a staff member inviting one specific, already-known person) need no schema at all: Supabase Auth's own admin invite-by-email (`supabase.auth.admin.inviteUserByEmail()`) already does this, called only with the service-role key from the Supabase dashboard directly — the same "operated outside the app" posture as applying a migration or minting the first Staff account (§5.3). `beta_invites` below exists only for the case that capability can't cover: a **shareable code** redeemable by someone whose email isn't known ahead of time. No admin UI is built for either path in V1 — email invites are a dashboard action, and code generation is a direct Supabase SQL-editor `insert`, consistent with how every migration in this project is already applied manually (§2), and proportionate to *"first 25 builders"* (`BETA_LAUNCH_CHECKLIST.md`).

```sql
create table public.beta_invites (
    code text primary key,
    created_by uuid references auth.users(id) on delete set null,
    used_by uuid unique references auth.users(id) on delete set null,
    max_uses integer not null default 1 check (max_uses > 0),
    use_count integer not null default 0 check (use_count >= 0),
    expires_at timestamptz,
    created_at timestamptz not null default now(),
    used_at timestamptz
);
```

`used_by unique` keeps this simple for the single-use-per-person case that fits a closed 25-person beta (one code, one person); `max_uses`/`use_count` are included so a single "Discord announcement" code good for several redemptions is possible without a schema change, without forcing that complexity into V1's actual usage.

**Redemption RPC**, called from signup:

```sql
create or replace function public.redeem_beta_invite(p_code text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_invite public.beta_invites;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in.';
    end if;

    select * into v_invite from public.beta_invites where code = p_code for update;

    if v_invite is null then
        raise exception 'Invalid invite code.';
    end if;

    if v_invite.expires_at is not null and v_invite.expires_at < now() then
        raise exception 'This invite code has expired.';
    end if;

    if v_invite.use_count >= v_invite.max_uses then
        raise exception 'This invite code has already been used.';
    end if;

    update public.beta_invites
        set use_count = use_count + 1,
            used_by = coalesce(used_by, auth.uid()),
            used_at = now()
        where code = p_code;

    return true;
end;
$$;
```

`for update` locks the row for the duration of the check-and-increment, closing the same race condition Milestone 19's SQL security audit found and fixed in `approve_component_submission()` — two people redeeming the last use of the same code at once must not both succeed.

**Signup flow:** an optional invite-code field added to the existing `pages/signup.html` form, called right after account creation succeeds (before or alongside `ensureProfile()`, mirroring the existing signup sequencing) — additive to signup, which is explicitly not part of what "do not redesign onboarding" protects (onboarding, per Milestone 21's own scope, begins *after* the first verified sign-in; signup itself predates it). While the beta is closed, the field is required (enforced client-side by a feature flag, not a schema constraint — the schema itself never forces an invite code, so turning the gate off for public launch is a config change, not a migration). **Discord-first onboarding** means operationally distributing codes via the Discord server once it exists (§4), not a schema concern — no code change is needed for *how* a code reaches someone, only for redeeming it once they have it.

**Feedback collection** for beta specifically reuses §9's `feedback_submissions` wholesale — a beta tester is just a user who redeemed an invite code; no separate beta-feedback mechanism is proposed.

---

## 11. Data Model — consolidated

Six new tables, one new column, one widened constraint. Every one is traced above to a specific section that has no other way to satisfy the request without it — none added speculatively.

| Object | Kind | Section | Why it's necessary, not speculative |
|---|---|---|---|
| `social_connections` | New table | §4 | No existing table can hold an OAuth identity mirror; required for display (§4.8) and re-sync (§4.5) to function at all. Shaped generically per §0.1, not Discord-specific. |
| `profile_roles` | New table | §5, §8 | Manually-awarded and permission-bearing roles need *some* persisted grant — automatic roles deliberately need none (§5.1). Merged from what could have been two tables (recognition + permission) — see decision below. |
| `content_reports` | New table | §8.3 | The literal capability being added; nothing today lets a user report anything. Re-confirmed separate from `moderation_actions` in §0.2. |
| `moderation_actions` | New table | §8.4 | Required by name in the request ("Audit logging"); kept separate from `content_reports` (see decision below and §0.2). |
| `feedback_submissions` | New table | §9 | The literal capability being added; nothing today collects feedback. |
| `beta_invites` | New table | §10 | Narrowed by §0.2 to only the shareable-code case — manual email invitations need no schema (Supabase's native admin invite covers that half). |
| `profiles.guidelines_accepted_at` | New column | §7 | One nullable timestamp; the same "essential, minimal" bar Milestone 21 held `onboarding_welcomed_at` to. |
| `notifications.type` CHECK widened | Modified constraint | §5.2, §8.4 | Two new values (`role_awarded`, `report_resolved`) so recognizing a role grant or resolving a report can notify someone through the *existing* notification system — reuses `create_notification()` verbatim, no new notification infrastructure. |

**Two explicit merge/split decisions, stated for review rather than silently made:**

1. **`profile_roles` merges what could have been two tables** (a `community_recognitions` table for Community Builder/Project Mentor, and a separate `platform_roles` table for Moderator/Staff). Merged into one `(user_id, role, granted_by, granted_at, note)` table with a composite `unique (user_id, role)` (a person can hold more than one role at once — e.g. a Moderator who's also a recognized Project Mentor) because the permission-vs-recognition distinction is meaningful in *what a role does* (§8.1's permission table), not in *how it's stored* — one clean table, one grant pattern, is simpler than two nearly-identical tables differing only in which values are allowed. `is_platform_moderator()`/`is_platform_staff()` (§8.1) express the "this role grants a permission" logic in the function layer instead.
2. **`content_reports` and `moderation_actions` stay two separate tables**, not merged into one "moderation events" table with a type discriminator. Considered and rejected: a report has a reporter and (until resolved) no actor; an action always has an actor and doesn't require a prior report. Forcing both shapes into one table would mean more nullable, conditionally-meaningful columns than two small, purpose-fit tables — the opposite of the minimalism the request asks for, even though it's fewer tables on paper.

**Explicitly not added:** a generic `roles` lookup/reference table (the seven role names are a fixed, small, code-reviewed `CHECK` list, not user-editable data — a lookup table would be exactly the "table just in case" the request says to avoid); a `reputation_score` column anywhere (§6); a `discord_guilds` table (§4.10, deferred until a second guild is a real requirement); a `moderation_dashboard_*` table of any kind (§8.2 — the dashboard reads the three tables above, it doesn't need its own).

---

## 12. Component Map

New/modified files, grouped by section. CSS reuses existing tokens/classes throughout — no new colors, no new badge-tier visual language (§5.4).

| File | Change | Section |
|---|---|---|
| `supabase/migrations/0026_social_connections.sql` | New | §4 |
| `supabase/migrations/0027_profile_roles.sql` | New — table + `is_platform_moderator()`/`is_platform_staff()` only (read-side; see below) | §5, §8.1 |
| `supabase/migrations/0028_moderation.sql` | New — `content_reports` + `moderation_actions` + `report_content()`/`resolve_report()`, **and** `grant_profile_role()`/`revoke_profile_role()` (moved here from `0027` during implementation — both need to log into `moderation_actions`, which doesn't exist until this file; same forward-reference constraint `0020`'s own header already documents for `catalog_moderators`/`is_catalog_moderator()`) | §8 |
| `supabase/migrations/0029_feedback_submissions.sql` | New | §9 |
| `supabase/migrations/0030_beta_invites.sql` | New — table + `redeem_beta_invite()` | §10 |
| `supabase/migrations/0031_guidelines_and_notification_types.sql` | New — `profiles.guidelines_accepted_at` + widened `notifications.type` CHECK + `notifications.build_id` relaxed to nullable + `create_notification()` given a default for `p_build_id` (needed so `0028`'s role/report notifications, which aren't about a build, can call it) | §7, §11 |
| `js/repositories/discordRepository.js` | New — `linkDiscord()`, `syncDiscordIdentity()`, `disconnectDiscord()`, `setDiscordVisibility()` | §4 |
| `js/repositories/communityRepository.js` | New — `getProfileRoles()`, `grantRole()` (moderator-gated), `reportContent()`, `submitFeedback()`, `redeemBetaInvite()` | §5, §8, §9, §10 |
| `js/services/communityRecognition.js` | New — `getAutomaticRole()` pure function (§5.1) | §5 |
| `js/components/RoleBadge.js` | New — one small reusable badge renderer, built on existing `.badge` class | §5 |
| `js/components/ReportButton.js` | New — reused inside comments and build pages | §8.3 |
| `js/components/FeedbackModal.js` | New — reuses `confirmDialog()`'s `<dialog>` construction pattern | §9 |
| `js/pages/settings/app.js` / `pages/settings.html` | Modified — new "Connected Accounts" section (Discord connect/disconnect/refresh/visibility) | §4 |
| `js/pages/profile/renderProfileHero.js` | Modified — one additional conditional list item for a public Discord link | §4.8 |
| `js/pages/build/renderComments.js` | Modified — adds the Report affordance to each comment | §8.3 |
| `js/core/layout.js` | Modified — one Feedback link in the footer | §9 |
| `pages/signup.html` / `js/pages/signup/app.js` | Modified — optional invite-code field, feature-flagged | §10 |
| `pages/legal/community-guidelines.html` | Modified — real section structure, placeholder copy | §7 |
| `pages/moderation.html` | **Not built this milestone** — named in §8.2 for a future pass | §8.2 |

---

## 13. Implementation Phases (for after this spec is approved — none of this is built yet)

Small, separately-verifiable, separately-committed phases, matching this repo's established convention:

1. **Schema — Discord.** `0026_social_connections.sql`, applied to a dev project only, per the standing procedure. *Commit: schema.*
2. **Schema — roles, moderation, feedback, beta.** `0027`–`0031`. Same dev-only application discipline. *Commit: schema.*
3. **Discord connect/disconnect/display.** `discordRepository.js`, Settings UI, `renderProfileHero.js`'s one additional list item. *Commit: Discord integration.*
4. **Automatic roles + role badge.** `communityRecognition.js`, `RoleBadge.js`, wired into the Builder Portfolio hero as one additive badge (§4.8-style small insertion, sign-off needed per §12). *Commit: community roles.*
5. **Manual role granting + moderator permission gate.** `is_platform_moderator()`/`is_platform_staff()` consumers, a minimal (no dedicated page yet) grant action reachable only by an existing Staff account. *Commit: moderator foundation.*
6. **Reporting.** `ReportButton.js`, wired into comments and build pages. *Commit: reporting.*
7. **Feedback.** `FeedbackModal.js`, footer entry point. *Commit: feedback.*
8. **Beta invites.** Signup field, redemption call, feature flag. *Commit: beta invites.*
9. **Guidelines page + acceptance gate.** Real page structure, the publish/comment-time acceptance check. *Commit: guidelines.*
10. **Tests** (§14). *Commit: tests.*
11. **Verification.** Static checks, axe-core, live-browser pass per §14.

---

## 14. Testing Strategy

Following this repo's established `tests/*.test.html` + `window.__testResults` convention:

- **`communityRecognition.test.html`** — `getAutomaticRole()` against fixture profiles/builds: brand-new account, active-but-young, long-term-and-active, long-term-but-dormant (falls back to a non-"long-term" bucket per §5.1's `hasRecentActivity` condition — an explicit boundary case worth naming here since it's easy to get backwards).
- **`discordRepository.test.html`** — mocked Supabase client: link success, link-denied, already-linked-elsewhere error surfaces the right message, sync idempotency (calling twice doesn't duplicate), disconnect removes both the Supabase identity and the mirror row.
- **`reportContent.test.html`** / **`feedbackSubmission.test.html`** — validation (empty reason/message rejected), the report-conflict-updates-not-duplicates behavior, category `CHECK` boundary cases.
- **`redeemBetaInvite.test.html`** — valid code, expired code, exhausted `max_uses`, and a concurrency case mirroring Milestone 19's `FOR UPDATE` fix (two redemptions racing the last use).
- **Accessibility** (§15): keyboard-only pass through Connect Discord → Settings' new controls, the Report button/dialog, the Feedback modal, and the guidelines-acceptance checkbox; screen-reader label check on `RoleBadge` (text content, not icon/color-only — same bar every other badge in this app already meets); mobile viewport check on the new Settings section and both new dialogs; `prefers-reduced-motion` on `FeedbackModal`/report dialog (both reuse `confirmDialog()`'s construction, which — as of Milestone 21 — has a verified, working reduced-motion path and correct centering; no new work needed there beyond confirming reuse, not reinvention).
- **Regression**: existing `tests/profile.test.html`, `tests/settings`-adjacent coverage, and `tests/comments.test.html` still pass unmodified after the Report-button addition.

---

## 15. Accessibility

- **Discord connect/disconnect**: real `<button>`s triggering a native browser OAuth redirect — no custom widget to make accessible, the flow is inherently keyboard-operable.
- **Role badges**: text-first (a role's name is always visible text, never conveyed by color/icon alone), reusing the already-accessible `.badge` pattern — no new a11y surface.
- **Report button and Feedback modal**: both build on `confirmDialog()`'s native `<dialog>` construction (focus trap, Esc, backdrop dismiss, and — per Milestone 21's fix — correct on-screen centering), the same proven base as the Milestone 21 Welcome/first-publish dialogs.
- **Guidelines acceptance**: a real `<input type="checkbox">` with a proper `<label>`, and the blocked action explains itself with visible text (not a title-attribute tooltip), matching the disabled-Publish-button convention already established in the editor.
- **Mobile**: Settings' new Connected Accounts section and both new dialogs follow the existing responsive card/full-screen-dialog patterns already in place — no new breakpoint behavior invented.

---

## 16. Definition of Done

- All six migrations (§12) written, reviewed, and — per standing instruction — applied to a **dev** Supabase project only, never production, until explicitly authorized.
- Every RPC has explicit `revoke ... from public` + a scoped `grant ... to authenticated` (or no grant at all, for functions only ever called from inside another `SECURITY DEFINER` function, matching `create_notification()`'s existing posture).
- No table in §11 has a client-facing `UPDATE`/`DELETE` policy where an RPC is the intended write path — direct-write gaps are exactly what Milestone 19's SQL security audit exists to catch, and the same review pass applies here before any migration is considered final.
- Automatic roles (§5.1) are verified computed-only — no code path writes a "current role" anywhere.
- No page introduces a numeric reputation display, a ranked list of builders, or a leaderboard of any kind — checked explicitly against §6 at review time, not assumed.
- Discord tokens are confirmed to never appear in any table this app controls — `social_connections` holds only public identity claims.
- `SCOPE.md`/`PRODUCT_ARCHITECTURE.md` updated per §1's recommended edits, or an explicit decision recorded not to, before this milestone is considered shippable — this spec does not update those files itself.
- Live-verified (desktop + mobile, keyboard-only, reduced-motion) per §14 before merge.
- Nothing pushed, merged, or applied to production until the complete milestone — not just this specification — is reviewed.

**Next step**: review §1's proposed governing-doc edits and §11's two merge/split decisions specifically — everything else follows from those. Nothing in this milestone is implemented yet.
