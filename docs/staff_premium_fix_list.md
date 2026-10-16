# Staff Premium, identity and cash: consolidated repair list

Updated 2026-10-16 after deploying and verifying the account-deletion follow-ups to Claude's uncommitted implementation. The
original 2026-10-14 findings below are retained as the repair specification;
the current status is recorded here. No commit was made by this review.

## Account-deletion review follow-up — 2026-10-16

The three latest findings are addressed in source without committing:

- Legacy flat product images are looked up by trusted Storage uploader ownership through service-only migration 0103, with foreign-shop references protected; cleanup handles nested folders and retries failed lookups/removals before deleting Auth users. Retained billing/shared files lose only the deleting accounts' Storage ownership metadata, so Auth deletion succeeds while the files and other accounts' ownership stay intact.
- Privacy EN/MY and Play Data safety reflect actual trial-claim deletion with the account. This change does not introduce a new retained identity or change the once-per-existing-account trial rule.
- Deleting an online account downgrades the same local shop to Free; it keeps records and pending outbox instead of opening a different empty shop. Paid/Free and post-signout paths have regressions.

Deployment completed in order: migration 0103 → activate → legal.allinonepos.app. Both helpers are service-only in production. A disposable Free test account verified legacy/nested file removal, billing-proof retention with detached ownership, preservation of an unrelated prefix, and successful Auth deletion. All synthetic files, bootstrap account and disposable subscription were then cleaned up; no real shop records, sale, payment or trial were used. Public policy bytes match the reviewed EN/MY file. Fresh deployment analyzer is clean and all 1,116 Flutter tests pass; the final code also passed 63 CI Deno and 217 SQL/migration/rollback tests before rollout. The rebuilt iPhone app is installed/launched; store AAB build 7 is prepared but not uploaded. No commit.

## Current completion review — 2026-10-15

### Follow-up implementation — 2026-10-15

The four remaining cases from the review below are now implemented and verified
in code. Analyzer is clean and the full Flutter suite passes **1,102 tests**;
six follow-up regressions also pass, including the added two-closed-snapshot
assertions. The original four tests were observed failing before implementation.
All 14 original items are now addressed in code; the previous partial status
below records the state before this follow-up. No commit has been made.

- Cash-read `AsyncError` shows a localized Retry action rather than a permanent
  spinner; opening remains disabled until the session read succeeds.
- Authenticated staff attachment/recheck stores its own `account:<uid>` actor
  in the existing shop-scoped active-identity key. Losing auth preserves that
  actor and the staff floor, including a cold offline Owner-PIN attempt.
  Unnamed/removed local staff sales are labelled Staff, not Owner. Owner login
  replaces that provenance normally. No new settings keys or schema were added.
- Equal opening timestamps use the same deterministic ID tie break for current
  session selection and movement allocation. A payment belongs to one session.
- Overlapping historical sessions expose a derived reconciliation without
  updating any stored close snapshot or sale. Reports, PDF, CSV and thermal
  output disclose the original expected cash and reconciliation change.
  Non-overlapping close snapshots retain their existing frozen behavior.
  History now watches session and cash inputs; a direct-sync invalidation test
  covers late session arrival and later payment updates. Balance Sheet uses
  the same equal-time tie break (its added regression failed at 0 instead of
  1,000 before correction). History rows directly show the original close and
  reconciliation change when variance is adjusted. A focused independent
  reviewer confirmed these follow-up ripple fixes.

Multi-shop actor isolation, retry UI, report exports and both-closed overlap
cases have been checked. Only mobile app code changed in this follow-up; no new
server migration/deployment is required. The final reviewed release built successfully (54.4 s) and was installed on
the paired iPhone through the native device installer. Launch verification
was refused by iOS because the phone is locked; the owner has been asked to
unlock it. No sale, account switch or till mutation was used for verification.

**Earlier review, superseded by the implementation above: 11 of the original
14 items were addressed, with items 5, 8 and 12 partial.** That review retained
Claude's work and identified the four cases below before the follow-up fixes.
No app source was changed during that review phase.

Addressed items: **1, 2, 3, 4, 6, 7, 9, 10, 11, 13 and 14.** This means the
implemented code and its regression checks cover the original identified
failure paths; it does not claim all physical-device flows have been verified.

- Items 1–2: Owner-only writes to both staff tables are implemented in migration
  0102. Read-only production inspection confirms SELECT remains shop-scoped,
  while INSERT/UPDATE/DELETE require `auth_is_shop_owner()`.
- Items 3–4, 6, 9: account-scoped handoff provenance, invited-staff promotion
  refusal, active/deleted PIN checks and grant removal, and unnamed identity
  clearing are implemented with regression coverage.
- Items 7, 10–11, 13–14: backup row-scope validation, bound cached-account
  fallback and verification UI, calendar/resume signal and invited-staff entry,
  supported-capability checks, and bounded branch refresh are implemented.
- Deployed `activate` and `admin` source was downloaded to separate temporary
  directories. Their shared `account_premium.ts` matches the working-tree module
  byte-for-byte; missing paid signing proof now returns a retryable error.

### Four remaining cases reproduced against Claude's current code

1. **Item 12 — cash read errors block daily entry permanently.**
   `DailyGate._detailsStep` sets `sessionLoading = premium && !hasValue`; an
   `AsyncError` also has no value. The actual widget displays loading and disables
   Continue, without a cash-read Retry action. Separate loading from error and
   show a retryable error path. Priority: high, as this blocks shop entry.

2. **Item 5 — auth loss loses cashier attribution while preserving Staff role.**
   Successful email attachment clears the old active cashier and uses the live
   email-linked profile. When backend role becomes null after session loss,
   actual `saleCashierIdProvider` falls into local Staff mode with a null selected
   ID, despite stored Staff role/account provenance. It returns null, which
   receipt formatting treats as Owner. Preserve trustworthy shop-scoped account
   attribution through auth loss, without restoring Owner or another cashier.
   Priority: high. Probe uses synthetic provider auth loss, not live signout.

3. **Item 8 — equal opening timestamps still double-count.**
   `_ownedBy` excludes only sessions with a strictly later `openedAt`. Two
   sessions with identical timestamps each allocate a single 1,000 payment;
   their expected-cash sum is 2,000. Add deterministic tie handling shared by
   queries, itemized reports and current-session selection. Priority: high.

4. **Item 8 — late overlapping sync conflicts with frozen close snapshots.**
   A closed session retains `expectedCashAtClose = 1,000`; a later-arriving
   overlapping open session also allocates that same payment as 1,000. Combined
   expected cash remains doubled. The closed report now lists cash-sales total
   zero while expected cash is 1,000. Handle this as an explicit reconciliation
   of a late overlap, preserving historical closed snapshots and sales instead
   of silently rewriting them. Priority: high; accounting semantics must be
   settled before choosing an implementation.

All four current-state diagnostic cases passed, asserting the observed defects
in an isolated test harness. No fake sale/till or auth mutation was sent to
production; the actual app source was not modified to make the tests pass.

### Fresh verification of Claude's work

- Analyzer: no issues.
- Full Flutter suite: **1,095 passed**.
- CI-selected Deno account/billing/sync suite: **56 passed**.
- CI-selected isolated PostgreSQL/migration/rollback suite: **209 passed**.
- Four additional isolated edge-case diagnostics: reproduced all four above.

Next execution order: retryable daily-entry cash errors, preserved offline
cashier identity, then deterministic/late-sync till reconciliation. Add actual
regression tests for those cases, rerun required checks, and only then rebuild
the device. The owner's no-commit instruction remains in force. The prior
changelog says Claude installed a release on the iPhone; this review has not
independently verified that installed binary or its physical offline flows.

## Original repair specification and investigation evidence — 2026-10-14

## Priority 1: authority, identity and records

1. **Enforce Owner-only server writes to staff permissions.** Deployed RLS
   and grants permit provisioned staff to insert/update/delete own-shop grants.
   Actual-policy local SQL tests reproduce insertion/update. Preserve staff
   reads, shop isolation and session/device checks; account for queued Owner
   changes and backup restoration. Sources: migration 0072 and
   `sync_force_apply`. Status: production metadata + isolated SQL reproduction.

2. **Protect staff-profile PIN/email/active administration on the server.**
   Deployed `staff_members` policy permits authenticated same-shop writes and
   has no Owner-check trigger. An isolated actual-policy SQL test reproduces
   staff changing a profile PIN and email. This also undermines email-based
   identity linkage. Preserve necessary roster reads and deliberate Owner
   operations; do not allow a staff client to edit another person's identity.
   Sources: migrations 0026/0073, staff repository and sync mapper.
   Status: production metadata + isolated SQL reproduction. **New item.**

3. **Keep deliberate Staff handoff independent from license recomputation.**
   Actual `LicenseController.recomputeExpiry()` restores local Owner when the
   signed-in account is Owner, leaving the selected cashier ID unchanged.
   Account attachment can establish role; the one-minute/resume/auth-event
   license recheck must preserve local PIN handoff. Source:
   `license_providers.dart::_apply`. Status: isolated controller reproduction.

4. **Preserve invited-staff restrictions when auth disappears.** A valid Owner
   PIN currently lets the controller persist local Owner for an email staff
   session. Effective role stays Staff until backend role disappears, then
   resolves Owner. Block unsupported role promotion in the controller and
   retain authenticated account provenance separately from local mode.
   This requires a valid Owner PIN; it is not a PIN-free bypass. Normal explicit
   staff signout reasserts Staff. Status: isolated provider/controller reproduction.

5. **Resolve the correct cashier at checkout from account identity.** Successful
   staff account attachment can leave another person's active ID or no ID;
   actual receipt formatting calls no ID Owner. Use the staff account's own
   unambiguous active linked identity for sale attribution, retain explicit
   shared-device PIN handoff for Owner sessions and clear stale attribution on
   account changes. Source: account attachment, staff providers, checkout,
   sales repository and `cashierNameForSale`. Status: isolated successful-login
   and formatting reproduction. Do not rewrite historical immutable sales.

6. **Revoke inactive local staff identity/PIN/grants promptly.** Removing a
   roster member hides it from the picker but actual PIN verification/controller
   still accepts it, and local permission resolution still grants Analytics.
   Check active/deleted state, invalidate/clear existing selections and stop
   grant inheritance. Treat local profile removal and email-account revocation
   explicitly: currently they are separate operations. Status: isolated
   repository/controller/provider reproduction.

7. **Validate legacy backup row scope before replacing shop data.** A backup
   without the envelope `shopId` is accepted even when its rows belong to another
   shop. Actual restore deletes target-shop rows and inserts foreign-shop rows.
   Infer and validate row scope for legacy files, reject ambiguous/mixed/wrong
   scopes before deleting, and preserve valid old backups. The modern explicit
   wrong-shop envelope guard already works. Source: `BackupService.importReplaceAll`.
   Status: isolated two-database restoration reproduction. **New item.**

8. **Handle overlapping cash sessions created by separate offline devices.**
   Each device can open its own shop-wide session; merging the rows leaves two
   open sessions, and actual `expectedCash` allocates the same cash payment to
   both time windows. Reconcile concurrent opens and avoid double allocation
   under the existing shop-wide till model. Do not silently discard sales,
   outbox rows or historical sessions. Source: cash repository and migration
   0041. Status: isolated two-device open/merge/payment reproduction, not a live
   sync conflict. This was a documented residual, now experimentally confirmed.
   **New item.**

## Priority 2: entry, verification and recovery

9. **Clear identity for unnamed Staff mode.** The no-name picker uses
   `switchRole('staff')`, which retains the previous cashier ID. Clear it so
   prior cashier attribution/grants cannot carry into unnamed mode.
   Status: isolated controller reproduction.

10. **Distinguish failed Premium verification from Free and from successful
    account attachment.** Failed-refresh fallback can return another user's
    cached license as success; enforcement rejects it, but the normal paywall
    shows Upgrade. Also, missing signing configuration can return a paid
    response without proof. Bind fallback to the actual identity and show a
    retryable verification state without weakening receipt checks or blocking
    core local sales. Status: isolated Dart and backend-handler reproductions.

11. **Separate authenticated identity from daily calendar entry.** Email staff
    should not choose Owner/another cashier each day. The daily provider caches
    its result without a date/resume signal; a changed stored date does not
    recompute until invalidation. Resolve account/roster loading safely, update
    on actual identity/shop/date changes, and retain PIN confirmation for
    deliberate shared-device handoff. Status: logic/code review plus cached-date
    reproduction. Physical midnight was not simulated with a real device clock.

12. **Wait for cash-session resolution and recover failed opening.** Actual
    daily-entry widget offers Open while the cash stream is loading. A duplicate
    open error propagates and leaves it busy/disabled. Await resolved state,
    catch errors and restore retry controls; distinguish a prior-day unclosed
    session from a new opening. Preserve today's optional opening policy until
    a mandatory cash-opening policy is explicitly decided. Status: actual
    widget reproduction with a mocked repository error + current query review.

13. **Make grants match supported actions for each account type.** Email staff
    normally cannot navigate to Owner cloud tiles from Settings; backend invite
    and branch switching remain Owner-only even if local capability grants exist.
    Explain/limit unsupported email-staff grants and align direct screen checks
    with the server. Local PIN handoff under an Owner email session is a distinct
    case. Status: navigation code review and handler denial reproductions.

14. **Bound branch-switch session refresh and offer recovery on timeout.**
    `BranchRepository.switchBranch` awaits two plain `auth.refreshSession()`
    paths without an application timeout. Installed GoTrue transport also has
    no request timeout at these call sites. A stalled transport can leave the
    switch pending after server claim changes. Use bounded refresh and persist
    a recoverable failed step, with no unsafe DB/outbox clearing. Status: source
    and installed-dependency review; no live network stall was induced.
    **New item.**

## Current verification completed

- `flutter analyze --no-pub`: no issues.
- Full current `flutter test --no-pub`: **1,076 passed**. Includes shop scope,
  settings, provider invalidation, pending-outbox transitions, sync recovery,
  staff, cash and backup checks. These are current baseline checks, not proof
  the defects above have been fixed.
- Account/backend existing checks: **16 Deno tests passed** across account
  Premium, social account and sync authorization; **16 isolated PostgreSQL
  authority tests passed** across role, revocation, capacity and session RLS.
- Consolidated temporary diagnostics: **11 Flutter, 6 Deno and 4 PostgreSQL
  cases passed**, asserting/reproducing current defective behavior alongside
  positive access controls. They are not implemented regression fixes.
- Server inspection used read-only account/shop/policy metadata queries.
  No real sale, permission, staff row, cash session or device binding was changed.

## Checks that currently passed without a new repair item

Modern wrong-shop backup envelopes are rejected; pending/stuck outbox guards
block unsafe clearing; per-shop settings and per-shop database file guards are
covered by passing tests. Provisioned staff cannot write another shop's data,
and unprovisioned staff cannot write protected business data in isolated RLS
checks. Banned membership/device-release authority checks also pass.

Device discovery found a wireless iPhone, but this environment does not provide
control/inspection of its installed app UI. It was not reinstalled, restarted,
signed out, disconnected or made to record a test sale. Thus live-phone offline
interaction, a physical midnight transition and an actual customer's receipt
are not claimed verified. Current code paths were investigated now with local
diagnostics; no request to postpone those investigations until after fixes is
being made.

Detailed chronology and evidence: `docs/staff_premium_daily_entry_review.md`.
