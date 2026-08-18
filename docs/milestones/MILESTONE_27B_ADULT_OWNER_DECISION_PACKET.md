# Milestone 27B — Adult Owner Decision Packet

**Who this is for**: an adult (parent, guardian, or other adult taking responsibility for Specbound) who is not necessarily technical, and who needs to make — or arrange for a lawyer to help make — the real decisions behind Specbound's legal pages and launch posture.

**What this is not**: this is not legal advice, and nothing in this document is a legal conclusion. It's a worksheet. Every item below explains why it matters, what Specbound's code and database actually do *right now* (verified by directly reading the code, not guessed at), the range of options a reasonable adult or lawyer might consider, and exactly what stays blocked until you answer it. No answer has been chosen for you anywhere in this document.

**Companion document**: `docs/milestones/MILESTONE_27B_LEGAL_READINESS_SPECIFICATION.md` has the full technical detail (with file/line citations) behind every claim made here, if you or a lawyer want to verify anything yourselves.

**How to use this document**: for each decision, fill in the blank "Decision," "Approver," and "Date" lines. Leave anything blank that isn't decided yet — a blank line is the honest, correct state until a real decision is made. Nothing in Specbound's product changes because a line in this document gets filled in; a filled-in decision here is the *input* to a future PR that actually builds or publishes something, never the action itself.

---

## 1. Who is the adult operator responsible for Specbound?

**Why it matters**: every other decision in this document, every legal document Specbound eventually publishes, and every account-deletion or moderation action that requires "adult-operator approval" (see `docs/OPERATIONS.md`) needs a specific real person attached to it — not just "an adult," but a named individual (or, if a business entity is formed, that entity acting through a named individual) who is actually accountable.

**Current product behavior**: Specbound's own internal documentation (`docs/OPERATIONS.md`, line 5) already states plainly that "Specbound's owner is a minor" and that legal publication, age-policy decisions, and account-deletion approval all require "an adult owner/guardian's direct action or explicit authorization." No specific adult has been named anywhere in the repository — this is intentional; no name, email, or other personal identifier for that person has been or should be put into this Git repository (see item 3 for why).

**Options to consider**: a parent or legal guardian of the minor owner; another trusted adult with the minor's and their guardian's agreement; a small business entity once/if one is formed (see item 2), acting through a named responsible individual.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 2. Should Specbound operate as an individual, or as a formal business entity — and is professional (legal/accounting) advice needed before deciding?

**Why it matters**: whether Specbound is "just a person's project" or a registered business (LLC, nonprofit, etc.) changes tax treatment, personal liability exposure if something goes wrong, what kind of Terms of Service makes sense, and who can sign contracts (like the Data Processing Agreements mentioned in item 17).

**Current product behavior**: not applicable — this is a business-structure question, not something the code determines.

**Options to consider**: continue as an individual-operated project for now, and revisit if it grows; form a business entity before public launch; consult a lawyer or accountant specifically about this question before deciding either way.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 3. What official business/contact email should Specbound use?

**Why it matters**: a Privacy Policy, Terms of Service, and DMCA/copyright process (item 15) all need a real contact address that isn't a personal email account, both for professionalism and so a personal inbox doesn't become the permanent public-facing contact forever.

**Current product behavior**: no contact email is published anywhere in the product today.

**Options to consider**: a dedicated email address just for Specbound (many providers let you create one for free or cheap); a role-based address like `support@` or `legal@` at a domain Specbound already controls (specboundapp.com); continuing to route everything through a personal address for now, with a plan to change it later.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 4. What lawful mailing/contact-address approach should be used, without ever putting a real home address into this Git repository?

**Why it matters**: some legal documents (and some state laws) expect a physical or mailing address for the operator of a service. A real home address must never be committed to this Git repository — Git history is effectively permanent and public (this repo is public on GitHub) — but a legal document may still need *some* address-equivalent.

**Current product behavior**: no physical address appears anywhere in the product or repository today, and none should be added by any future PR without going through this decision first.

**Options to consider**: a registered agent or business-formation service that provides a legal address (common if item 2 results in forming an entity); a P.O. box; a virtual mailbox service; consulting a lawyer about what's actually required for your situation before assuming an address is needed at all.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 5. Which countries/states should Specbound target for public launch?

**Why it matters**: Specbound's code has no geographic restriction today — anyone anywhere with an invite code can already sign up. Different places have different privacy laws (see the specification document §8 for the specific ones already researched: Virginia, and — only if relevant to your answer here — California, the EU, and the UK). Deciding where you actually want users from is what determines which of those laws are worth reviewing at all.

**Current product behavior**: no geographic restriction of any kind exists in the code today (verified by search, not assumed) — see specification §3/§8.

**Options to consider**: U.S.-only launch; U.S. plus specific other countries; worldwide with no restriction; worldwide but with specific jurisdictions you choose to exclude for legal-complexity reasons.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 6. What is the minimum age to use Specbound?

**Why it matters**: this is one of the most consequential decisions in this whole packet. U.S. federal law (COPPA) imposes serious, specific obligations — including a parental-consent process — on any service that knowingly collects personal information from children under 13. Specbound's Community Guidelines page already describes the intended audience as including teenagers, but nothing in the actual signup flow checks anyone's age at all.

**Current product behavior**: no age field, no birthdate collection, no age checkbox, and no minimum-age statement exists anywhere in the signup form or anywhere else in the product (verified directly — see specification §2/§3/§7). Anyone who obtains an invite code can create an account today, regardless of age.

**Options to consider**: set a minimum age (commonly 13, sometimes 16 or 18) and add an age-attestation step at signup; explicitly prohibit users under 13 and design signup/enforcement around that; build a legally-reviewed parental-consent system to knowingly support under-13 users (this is a significant undertaking — see the FTC's own compliance-plan resource linked in the specification document, §17); consult a lawyer before deciding, given how much COPPA exposure turns on this exact choice.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 7. If users under 13 are ever supported, what does the parental-consent process look like — and if not, how is that enforced?

**Why it matters**: this only needs an answer once item 6 is answered. If under-13 users are prohibited, you need a real (even if imperfect) way to say so and act on it. If they're supported, COPPA requires a specific verifiable-parental-consent mechanism — this is not something to build without legal review, given the FTC's active enforcement posture in this area (see specification §7/§17).

**Current product behavior**: nothing exists today either way — no age check, no consent flow, no enforcement mechanism.

**Options to consider**: an age-attestation checkbox at signup, with account termination if later found to be false; a legally-reviewed parental-consent flow (verifiable consent, not just a checkbox — COPPA is specific about what counts); explicitly deciding under-13 support is out of scope indefinitely.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 8. Do teen users (13-17) need additional safeguards beyond what adult users get?

**Why it matters**: COPPA itself doesn't reach 13-17-year-olds, but the FTC has separately signaled concern about teen privacy, and some state laws (including Virginia's, which has recently been the subject of active enforcement specifically around minors' social-media use — see specification §17) treat minors differently from adults in ways that go beyond COPPA's under-13 line.

**Current product behavior**: Specbound treats every account identically today regardless of any age signal, because no age signal is ever collected (item 6). There is no different behavior, privacy default, or safeguard for a 14-year-old's account versus a 40-year-old's.

**Options to consider**: no differentiated treatment; stricter default privacy settings for teen accounts (e.g., a private-by-default profile, since profiles are fully public by default today — see specification §3); additional content or contact restrictions; consult a lawyer about what Virginia's minor-specific provisions actually require, if anything, before deciding.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 9. Should public signup stay closed (invite-only) until legal review is complete?

**Why it matters**: this is the one decision that, if left unanswered, defaults to the safest option automatically — signup already requires an invite code today, and nothing in this PR changes that.

**Current product behavior**: signup is gated by a single on/off flag in the code (`BETA_INVITE_REQUIRED`), currently set to require an invite code. It is a one-line code change to turn off, not a database change — meaning this decision, once made, is easy for a developer to act on, but the decision itself (when it's safe to flip that switch) belongs entirely to you.

**Options to consider**: keep it invite-only until every item in this packet is answered and any resulting legal pages are published; keep it invite-only until a specific subset of items is answered (name which ones); open it at a specific future date regardless of remaining items (not recommended without at least the age and privacy-policy decisions settled, but your call).

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 10. What data-retention periods are acceptable?

**Why it matters**: right now, almost nothing in Specbound's database automatically expires or gets deleted on a schedule — reports, feedback, audit logs, and most other records persist indefinitely unless a person manually deletes an account (see specification §3/§4). Some privacy laws expect a stated retention policy, even if that policy is "we keep it until you delete your account."

**Current product behavior**: no automatic deletion/expiration (no "TTL," no scheduled cleanup job) exists for any table in the database today — confirmed by directly searching the database migration files, not assumed.

**Options to consider**: formally adopt "indefinite, until deletion is requested" as the stated policy (matches current reality, simplest to implement); set specific retention windows for specific categories (e.g., closed feedback purged after N years) and build the cleanup logic to match; something in between, decided category by category using the data-category matrix in the specification document (§4) as a starting checklist.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 11. What should the account-deletion process be, and how should "legal hold" situations be handled?

**Why it matters**: Specbound has no self-service "delete my account" button today — only a detailed, manual, staff-run procedure that has never actually been run against real production data and requires your personal sign-off for every individual case (see `docs/OPERATIONS.md` §10, summarized in the specification document §3/§4/§10). That procedure already reflects one real decision that's already been made — that a departing user's published projects get permanently deleted along with their account, not anonymized or kept — but several things around it are still open.

**Current product behavior**: manual-only deletion, gated on your explicit case-by-case approval; builds/projects are hard-deleted (not kept or anonymized); most other data either cascades away automatically or has the person's identity stripped out and the record kept (see the specification's data-category matrix, §4, for the exact table-by-table behavior). There is currently no concept of "legal hold" (pausing deletion because of a legal dispute or investigation) anywhere in the system — if that need ever comes up, nothing today would stop a normal deletion from proceeding.

**Options to consider**: keep the current manual, you-approve-every-case process as the permanent design (simplest, but doesn't scale past a small number of users); build a self-service deletion flow, once you decide exactly what it should and shouldn't delete; add a legal-hold flag/mechanism now, before it's ever needed, versus deciding to build it only if a real situation arises.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 12. How should anonymized feedback and moderation-audit records be treated?

**Why it matters**: two specific, already-built pieces of Specbound's design touch this directly. First, feedback someone submits (bug reports, suggestions) is designed to survive their account being deleted — their identity is stripped out, but the feedback text stays, forever, by design (see specification §3/§4). Second, the internal moderation audit log (who took what moderation action, and when) gets *deleted* if the moderator who authored those actions later deletes their own account — which is the opposite of what you'd usually want from an audit trail, and Specbound's own procedure already flags this as something requiring your explicit acknowledgment every time it comes up, rather than letting it happen silently.

**Current product behavior**: feedback → kept forever, identity removed. Moderation-audit entries → deleted if the moderator who wrote them deletes their own account (no way in the current database design to keep the record while removing the person).

**Options to consider**: accept both behaviors as-is; keep anonymized feedback but set a maximum retention period; decide the moderation-audit-deletion behavior needs to change (this would require a database change, not just a policy decision — flag it if you want it revisited) or decide it's acceptable given how rarely a moderator would also be the one deleting their own account.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 13. What ownership and license does Specbound need over the content users post?

**Why it matters**: when someone publishes a build, photos, and descriptions on Specbound, a Terms of Service normally has to say who owns that content (almost always: the user who created it) and what rights Specbound needs from them to actually display it, back it up, and let other users see it. Right now, nothing in Specbound's Terms says this, because the Terms don't exist yet.

**Current product behavior**: content is stored and displayed exactly as uploaded; Specbound's Community Guidelines already informally expect users to only post their own work or properly credit others (see specification §6/§9), but this is a conduct expectation aimed at other users, not a license grant from users to Specbound.

**Options to consider**: a standard "you own it, you grant us a license to host and display it" clause (the common approach for user-generated-content platforms); something more specific to Specbound's use case (e.g., addressing whether Specbound can ever use a user's project in its own marketing); consult a lawyer for standard UGC-platform license language rather than drafting from scratch.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 14. What content is prohibited, and how should enforcement work?

**Why it matters**: Specbound already has real, working content rules — the Community Guidelines page — but a Terms of Service usually needs its own, more formal version of this, with clearer legal consequences (suspension, termination, content removal) than a conduct-guideline page typically states.

**Current product behavior**: the Community Guidelines page (finalized, live, versioned — see specification §6) already covers harassment, hate speech, spam/scams/impersonation, plagiarism/content-authenticity, dangerous/illegal activity, and a report-and-review enforcement process, explicitly stating there's no formal appeals process today. A report/moderation system is already built and working (see specification §3, `content_reports`/`moderation_actions`).

**Options to consider**: adopt the existing Community Guidelines language as the basis for a formal Terms of Service enforcement section, rather than writing a second, separate set of rules; decide whether a formal appeals process should be built (currently explicitly absent); decide whether anything in the existing Guidelines needs to change once real Terms exist alongside it.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 15. Who is the copyright/DMCA contact, and what's the takedown process?

**Why it matters**: U.S. law (the DMCA) offers online services a legal "safe harbor" from copyright-infringement liability for content users post — but only if the service properly designates and registers an agent to receive takedown notices, through the U.S. Copyright Office's own official system (linked in the specification document, §17), and follows a real notice-and-takedown process.

**Current product behavior**: no copyright/DMCA contact, page, or process exists anywhere in the product today. No agent has been registered with the U.S. Copyright Office. This is a real, currently-unaddressed gap — not a decision that's already been made either way.

**Options to consider**: designate a contact (likely the same email as item 3) and register it with the Copyright Office once ready; consult a lawyer about whether formal DMCA safe-harbor registration is worth the effort at Specbound's current size, versus just building a basic "report copyright infringement" flow using the existing reporting system as a starting point.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 16. What analytics/cookies should Specbound use going forward?

**Why it matters**: Specbound's own application code sets **no cookie of any kind**, and the only "tracking" it performs is a single anonymous, random identifier stored in the visitor's own browser purely to stop the same visitor from inflating a project's view count — it's never sent anywhere else and isn't tied to any account (see specification §3/§11). Separately — and outside anything this codebase controls — Cloudflare, the company that hosts Specbound, automatically adds its own Web Analytics (which Cloudflare itself describes as cookieless) and, on at least the custom production domain, a Bot Management challenge system that can set its own `cf_clearance` cookie on a visitor who is challenged and passes. That cookie, when set, applies to Specbound's own domain — not a third-party tracker — so it is not accurate to tell a reader that visitors can never receive any cookie at all.

**Current product behavior**: no cookie is set by this application's own code; one anonymous localStorage identifier (view-count dedup only); the browser's normal sign-in session token (also not a cookie, stored the way the login library does it by default under this app's current, unmodified configuration); Cloudflare's own edge-injected, cookieless Web Analytics; and Cloudflare's Bot Management system, which may conditionally set a `cf_clearance` cookie (Cloudflare's default: 30 minutes) on a visitor challenged on at least the custom domain — independent of anything in this repository (see specification §11 and §17 for the official Cloudflare source).

**Options to consider**: keep the current minimal application-level footprint and describe it accurately in a future Privacy/Cookie Policy — including Cloudflare's own edge-level Web Analytics and conditional Bot Management cookie, rather than an unqualified "no cookies" claim; add first-party analytics later if you want usage insight beyond what Cloudflare already provides, and revisit this decision then; decide whether Cloudflare's Bot Management challenge cookie needs its own disclosure line in a future Privacy/Cookie Policy even though it isn't something the app code sets or controls; consult a lawyer about whether a conditionally-set vendor security cookie changes what a Cookie Policy needs to say.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 17. Do any vendor Data Processing Agreements need to be reviewed or signed?

**Why it matters**: Specbound relies on Supabase (database/auth/file storage) and Cloudflare (hosting/security) as data processors. Both companies publish standard Data Processing Agreements (linked in the specification document, §17) that govern how they're allowed to handle the data Specbound sends them. Depending on which laws end up applying to Specbound (item 5 and the jurisdiction items), formally reviewing or executing these may or may not be necessary.

**Current product behavior**: Specbound uses both vendors' standard/default terms today; no custom DPA has been separately reviewed or executed as part of this project's own record.

**Options to consider**: review Supabase's and Cloudflare's published DPAs (both link directly from the specification document) and decide if anything needs to change; consult a lawyer about whether formal execution is necessary given your answers to items 5 and 2; decide it's not necessary at Specbound's current scale and revisit later.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 18. What's the process if there's ever a data breach or security incident?

**Why it matters**: many privacy laws (including Virginia's) require notifying affected people, and sometimes regulators, within a specific timeframe if personal data is exposed in a breach. Specbound currently has no defined process for this at all — not because a decision was made against having one, but because it's never been addressed.

**Current product behavior**: no incident-response process, breach-notification template, or designated security contact exists anywhere in the product or its documentation today (verified — this is a genuine, real gap, not an oversight in this document).

**Options to consider**: write a basic internal incident-response checklist (who to notify, how fast, using what contact method) even before anything happens; consult a lawyer about what's actually legally required for your target jurisdictions (item 5) before drafting a formal process; treat this as a pre-launch requirement rather than something to defer.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 19. Is there an accessible way for someone with a disability, or with a legal question, to reach a real person?

**Why it matters**: beyond the general contact email (item 3), some legal frameworks and good practice generally expect a real, working way for someone to reach a human about accessibility concerns or legal requests specifically — not just a generic support inbox that might not route those requests appropriately.

**Current product behavior**: no dedicated accessibility or legal contact mechanism exists beyond whatever general contact method item 3 resolves to.

**Options to consider**: use the same general contact email for everything, at least initially; set up a separate address specifically for accessibility or legal requests once volume justifies it; note in the eventual Privacy Policy/Terms exactly how to reach you for each kind of request.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 20. Who gives final approval to publish each public legal document?

**Why it matters**: Privacy Policy, Terms of Service, Cookie Policy (if built), and any Copyright/DMCA page each need one clearly identified adult who actually signs off before it goes live — not an implicit assumption that "someone" approved it.

**Current product behavior**: no legal document has been published (see specification §6), so no approval has happened yet for any of them.

**Options to consider**: the same adult operator named in item 1 approves everything; different documents get approved by different people (e.g., a lawyer specifically approves final legal wording, while the adult operator approves the decision to publish); require both a lawyer's review *and* the adult operator's separate sign-off before anything publishes.

- [ ] Decision (Privacy Policy approver): ___________________________________________
- [ ] Decision (Terms of Service approver): ___________________________________________
- [ ] Decision (Cookie Policy approver, if built): ___________________________________________
- [ ] Decision (Copyright/DMCA page approver, if built): ___________________________________________
- Date: ___________________________________________

---

## 21. Should an attorney review any or all of this before publication?

**Why it matters**: nothing in this packet or the specification document is legal advice, and several of the decisions above (especially the age/COPPA question in items 6-8, and the jurisdiction question in item 5) carry real legal risk if gotten wrong. This decision is squarely yours — this document deliberately does not recommend for or against hiring a lawyer, only flags where the stakes are highest.

**Current product behavior**: not applicable.

**Options to consider**: full attorney review of all final legal documents before publication; attorney review limited to the highest-stakes items (age/COPPA, and whichever jurisdictions item 5 selects); no attorney review, proceeding on your own judgment and the official-source links provided in the specification document (§17).

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## 22. Approval date, version, and change-log process for legal documents going forward

**Why it matters**: once real legal documents exist, they'll need to change over time (the Community Guidelines page already does this correctly today — see specification §6 — with a version date and a defined re-acceptance mechanism). Deciding the process now, even before real Privacy Policy/Terms text exists, means the first version is built the right way from day one instead of needing to be retrofitted later.

**Current product behavior**: the Community Guidelines page's existing versioning approach (a `CURRENT_GUIDELINES_VERSION` constant, a "Last updated" date on the page, and a stored per-user acceptance record that becomes stale when the version bumps) is a working, already-built example of exactly this pattern — see `js/config/guidelines.js` and migration `0034` in the specification document.

**Options to consider**: reuse the same version/re-acceptance pattern already built for Community Guidelines, for the Privacy Policy and Terms as well; use a simpler "last updated" date only, without a forced re-acceptance flow; decide case-by-case which future changes are significant enough to require re-acceptance versus just updating the date.

- [ ] Decision: ___________________________________________
- Approver: ___________________________________________
- Date: ___________________________________________

---

## Summary checklist

Use this as a quick at-a-glance view. Nothing here is checked off by this document — check a box only once the corresponding decision above has a real answer, approver, and date filled in.

- [ ] 1. Adult operator named
- [ ] 2. Business-entity question resolved
- [ ] 3. Official contact email chosen
- [ ] 4. Lawful address approach chosen (no home address in Git, ever)
- [ ] 5. Target countries/states decided
- [ ] 6. Minimum age decided
- [ ] 7. Under-13 approach decided (prohibited, or reviewed parental-consent system)
- [ ] 8. Teen (13-17) safeguards decided
- [ ] 9. Signup-closed-until-review posture confirmed or changed
- [ ] 10. Data-retention periods decided
- [ ] 11. Account-deletion and legal-hold approach decided
- [ ] 12. Anonymized feedback / moderation-audit retention decided
- [ ] 13. User-content ownership/license decided
- [ ] 14. Prohibited-content and enforcement approach finalized
- [ ] 15. Copyright/DMCA contact and process established
- [ ] 16. Analytics/cookie approach decided
- [ ] 17. Vendor DPA review decided
- [ ] 18. Incident/breach-notification process defined
- [ ] 19. Accessibility/legal contact mechanism decided
- [ ] 20. Final approvers named for each legal document
- [ ] 21. Attorney-review decision made
- [ ] 22. Version/change-log process decided

---

## Related documents

- `docs/milestones/MILESTONE_27B_LEGAL_READINESS_SPECIFICATION.md` — full technical detail and source citations behind every item above.
- `docs/OPERATIONS.md` §10 — the account-deletion procedure referenced in items 11-12.
- `docs/ROADMAP.md` — where this milestone sits relative to the rest of Specbound's plan.
