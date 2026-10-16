# Staff Premium and daily entry review

Original investigation recorded 2026-10-14. Updated 2026-10-15: Claude has
implemented and reportedly deployed the repair set without committing. Fresh
review confirms 11 of 14 original items addressed, with items 5, 8 and 12 partial;
four remaining cases are reproduced and recorded at the top of
`docs/staff_premium_fix_list.md`. Deployed staff RLS and the shared activate/admin
module were verified read-only. The chronological evidence below describes the
original investigation; statements that no fix was deployed apply to that phase.

Follow-up update: the four remaining cases are now implemented. Fresh analyzer
is clean, 1,102 Flutter tests pass, and six follow-up regressions cover cash-read
retry, persistent offline staff attribution/floor, equal-time sessions, both
closed snapshots, reconciliation exports and shop isolation. Original close
rows remain unchanged; derived reconciliations are explicitly shown in reports.
The earlier review's 11/14 status is historical; see the latest implementation
section in `docs/staff_premium_fix_list.md`. No commit has been made.

## Report and scope

The consolidated current repair list is now
`docs/staff_premium_fix_list.md` (14 items), after verification of the previously
listed follow-up scenarios in this same investigation. Consult that list for
current priority and qualification; the sections below retain the evidence
chronology.

The owner bought Premium and invited staff. Staff email login shows Free/Upgrade
and cannot use Premium features. The owner requested a review of account-based
identity and daily entry, including repeated user selection and cash opening,
then asked to retain the recommendation and investigate further.

## Confirmed from current code

- Premium belongs to `shop_subscriptions`, not exclusively to the owner login.
  `activate/index.ts` allows staff through `refresh_account_license`, calls
  `register_shop_device`, then signs a receipt for the calling staff user and
  device. Owner permission is required for trial and branch switching, not for
  this refresh. Three active devices are allowed on Premium, including owner,
  staff and browser devices.
- `resolveEntitlement` requires the signed user, device, shop and revision to
  match. Reusing an owner's receipt after logging in as staff correctly fails.
  Do not relax these checks to make staff Premium work.
- `AccountRepository.attachAccountLicense` returns a supplied cached license
  as success on a network/server error without validating its receipt against
  the new user. A same-shop account change can therefore appear successful
  while Premium remains verification-required. This is a concrete failure
  path in code, not yet a reproduction of the reported production incident.
  `PremiumGate` displays its normal Upgrade paywall for verification-required
  as well as genuinely Free/lapsed states; this hides the distinction.
- Email staff permissions use `emailLinkedStaffMemberProvider`, matched to an
  active roster row by email. Checkout records `activeStaffIdProvider` instead.
  Account attachment writes the local role but does not bind/clear the active
  roster identity. Email account and cashier attribution can consequently
  disagree; a staff login must not choose another person's cashier identity.
- Daily identity is intentionally repeated whenever a roster exists, even
  with a signed-in email account (`shouldSkipDailyGateIdentity`). The UI lists
  Owner and all active roster members. Authenticated staff remains effectively
  staff, so choosing Owner does not grant owner permission, but the selection
  is misleading and unrelated roster selections can misattribute sales.
- Daily completion is per shop and local calendar date, not per account or
  shift. The provider reads the date when evaluated; it has no midnight timer
  or lifecycle date signal. An app left running across midnight can retain
  yesterday's resolved result. Same-day user changes must update identity
  independently of this daily marker.
- Opening amount appears only when Premium is true and no open cash session
  is currently available. The session is shop-wide: `watchCurrentSession`
  filters by shop, not device. A prior-day unclosed session still counts as
  open. The UI offers Skip; checkout currently does not require an open till.
- Cash-session stream loading is treated as absence via `valueOrNull`.
  `openSession` guards against duplicate opens inside a local DB transaction,
  but the daily gate's open action has no error recovery for a duplicate-open
  race. Offline concurrent opening on different devices remains a documented
  limitation. Do not promise independent tills without redesigning accounting.

## Recommended behavior to preserve for implementation

1. Resolve shop entitlement independently from owner/staff permissions. Staff
   inherits the selected shop's Premium after trusted membership and device
   provisioning succeed, within the three-device limit.
2. Distinguish Free, expired, verification pending, network failure and device
   capacity errors. A failed refresh must not claim successful Premium
   attachment with another user's receipt. Keep core local selling available.
3. For an individual staff email login, bind the cashier to that staff profile
   automatically. Prefer a stable backend user ID link over email matching;
   handle unlinked/duplicate profiles explicitly. Never offer other staff or
   Owner identities to an authenticated staff session.
4. Owner email login establishes Owner identity. Keep explicit staff handoff
   with PIN for shared devices. Restore Owner deliberately and clear stale
   active-staff attribution. Do not overwrite a deliberate staff handoff on
   every token refresh or app restart.
5. Keep an authenticated session across days; do not require email/password
   or repeat identity selection just because the date changes. Shared-device
   unlock/handoff remains a separate local PIN action.
6. Resolve cash state separately from account login. Wait for session loading,
   continue the existing shop-wide open session, and offer opening only when
   needed. Show an unclosed prior-day session for review instead of silently
   creating another. Owner browsing reports does not need to open the till.
   Whether cashier opening is mandatory or optional is a product decision;
   preserve today's optional selling until that policy is explicitly settled.
7. Reevaluate date/session state on resume and across midnight. Daily calendar
   completion is not proof that the register is still open or the current
   cashier is unchanged. Scope settings to the shop and preserve multi-shop
   separation.

## Verification completed

- Earlier investigation: 31 Flutter tests passed across daily gate logic,
  entitlement, account-license lifecycle and staff license-screen protection.
- Further investigation: 68 Flutter tests passed across daily navigation,
  staff, account identity, cashier labels and cash sessions.
- 9 Deno account-Premium tests passed, including receipt bindings/signature
  checks and actual HTTP-handler coverage for existing tested actions.
- 16 isolated local PostgreSQL authority tests passed, including staff device
  registration, revoked membership, capacity and session-bound RLS. These use
  temporary local databases, not production.

Existing tests confirm current behavior; they do not reproduce the reported
staff login incident or prove the proposed behavior has been implemented.
No full analyze/test run or device deployment was required for this notes-only
change. No production account data was accessed.

## Next checks before implementing a fix

### Additional diagnostic reproduction (2026-10-14)

Five temporary diagnostic cases were run against actual repository functions
and the exported backend account-action handler, with in-memory/mock data and
no production connection. These are probes of current behavior, not fixes:

- The backend handler successfully returns Monthly Premium and a signed
  receipt bound to the staff user, shop and device on staff refresh.
- A device-capacity rejection remains `device_limit_reached`; this handler
  does not silently turn it into a Free subscription.
- A Free subscription in server authority is returned as Free for staff too.
- Missing signing configuration returns `ok: true` and a paid plan without a
  receipt. The client must reject this for Premium. This server misconfiguration
  is another distinguishable failure mode, not evidence it exists in production.
- The Dart repository returns successful attachment on a failed network refresh
  using a supplied owner's cache; actual `resolveEntitlement` with enforcement
  enabled rejects the owner receipt for the staff user. Local role becomes
  staff. The existing active cashier ID is not cleared or rebound.

The Dart probe passes `enforce: true` directly, because ordinary Flutter tests
without build-time backend definitions skip receipt enforcement. Passing the
existing lifecycle tests alone therefore cannot prove staff receives a valid
production receipt. The supplied entitlement in this probe is parsed test data;
the probe covers identity resolution, not Ed25519 verification or live password
login. Signature behavior is covered separately by existing receipt tests.

The exact reported production cause remains unknown. Subsequent read-only
production checks are recorded below. No account/device authority was changed.

### Targeted production inspection (2026-10-14)

After the user supplied an email, the linked All In One POS project's Management
API was available through the authenticated CLI. Queries were scoped to that
account and its related shop. Passwords, PINs, access tokens, private signing
material and session IDs were excluded; account email values are not retained
in this repository note.

- The supplied email identifies the **owner**, not staff, of `My Shop`.
- Its subscription is Yearly, revision 7, unarchived, expiring
  2027-10-16 16:14:30 UTC (2027-10-17 00:14:30 Asia/Singapore).
- The shop has one active device, bound to the owner, with a session binding.
  Its recorded activity is 2026-10-14 03:54:39 UTC. Capacity is not full.
- One related real staff account exists. Trusted membership resolves to staff,
  it is not banned, and exactly one active roster profile matches its email.
  Its last password/social sign-in timestamp is 2026-10-05 06:42:00 UTC.
- That staff account currently has **zero active device bindings**. Neither
  account membership nor roster linkage alone grants cloud/Premium access:
  successful authenticated device provisioning is also required.
- A second historical device row is released and has no session binding.

These results rule out expired owner Premium, a full three-device roster, banned
staff and missing email/roster linkage for this related account at inspection
time. They establish missing current staff device authority, but do not prove
why: staff attachment may never have succeeded, or later owner login on the same
physical device may have rebound the row. The user has been asked to confirm
whether the related staff email is the account exhibiting the reported symptom.
Next reproduce that account's authenticated refresh and examine the result and
the device/session transition. Do not manually relabel the owner's current
device or share owner receipts to bypass this requirement.

### Confirmed recovery and follow-up (2026-10-14)

The user reports Premium is now available and supplied a screenshot of the
related staff email with a Staff badge and Yearly plan. The account card renders
the cached plan, so the screenshot alone is not cryptographic proof of Premium;
the user's feature-use report and server checks provide additional evidence.

Read-only production recheck confirms:

- Trusted role remains staff and the account is unbanned. A new sign-in occurred
  at 2026-10-14 03:56:18 UTC (11:56:18 Asia/Singapore).
- Staff now has one active device with a session binding, last active at
  03:57:27 UTC. Total active shop devices remains one; Yearly expiry is unchanged
  and subscription revision is now 8. No authority was changed by this review.
- The matching staff profile has all seven current capabilities: analytics,
  inventoryEdit, staffAccounts, branches, storefront, license and
  settingsSensitive. Analytics visibility in the screenshot matches the grant;
  it does not indicate the account became Owner. Confirm broad grants reflect
  the owner's intended responsibilities before changing any of them.
- There are no open cash sessions on the server and no synced sales created
  after that staff sign-in at query time. This cannot establish local offline
  state or validate actual sale/receipt attribution yet.

Further code/handler review found a permission mismatch: the Flutter staff
accounts and branch screens accept their respective capability grants, but the
backend still requires Owner for staff invitation and branch switching. Two
additional temporary handler probes reproduce `forbidden` for staff in those
actions. The six backend diagnostic cases now pass, documenting current
behavior. Align visible actions with the backend policy; do not weaken backend
ownership checks as an incidental Premium fix.

Follow-up qualification: `SettingsScreen` explicitly hides Owner cloud tiles
for authenticated email staff and also checks `session.backendRole != 'staff'`.
The backend denials do not establish that normal staff Settings navigation
exposes those actions. The mismatch concerns granting capabilities that are
not supported for email staff and the screens' own less restrictive entry
checks. An internal/direct screen entry is different from a reachable normal
Settings action. This corrects the earlier overly broad description.

### Successful-login cashier probes (2026-10-14)

Two additional isolated Dart repository diagnostics reproduce successful staff
attachment (a mocked successful paid refresh), rather than only the previously
tested failed-refresh fallback:

- An unrelated preselected cashier ID remains selected after staff attachment.
- With no prior cashier selection, successful staff attachment leaves the ID
  null. Actual `cashierNameForSale` renders that null attribution as Owner.

The temporary Dart diagnostic suite now has three passing cases. Checkout's
actual `staffId` argument reads this same local active ID, and the sales
repository stores it verbatim; account-email profile matching for permissions
does not repair sale attribution. This reproduces the identity defect in local
logic, not an observed wrong production sale. A further read-only cloud check
still found zero synced sales created after the staff login and no open till.
The local phone/outbox cannot be inspected from cloud results.

Cashier attribution is a high-priority remaining correctness issue:
resolve a signed-in email staff's own linked identity at the sale boundary,
fail clearly if that link is missing/ambiguous, and preserve explicit PIN
handoff only for shared Owner sessions. Do not modify historic immutable sales
or infer a cashier for them from whichever email is logged in today.

### Local handoff, removal and till-loading diagnostics (2026-10-14)

Four additional temporary diagnostic tests pass against current local code:

1. **Local roster removal does not revoke local PIN access/grants.** Create a
   named member with Analytics access, deactivate the member, then call actual
   `StaffController.switchToStaffMember` with its correct PIN. Authentication
   still succeeds, active identity is set, and actual
   `hasOwnerCapabilityProvider(analytics)` still resolves true in local PIN mode.
   `verifyPin` reads by ID without checking active/deleted state; the grant
   watcher does not require an active roster row. The ordinary picker hides
   inactive members, so this is not evidence they remain visible in that UI;
   it matters for a stale selection or an already active local session. This
   is distinct from server staff-account revocation and email staff's
   active-profile matching. Revoke identity/grants promptly on roster changes.
2. **Unnamed Staff handoff preserves the previous identity.** After named
   staff selection, `switchRole('staff')` leaves the active member ID unchanged.
   This is the controller path used by the "no name" picker sentinel. Clear
   it for unnamed mode so the previous person's sales/grants cannot carry over.
3. **Daily completion is cached until invalidated.** A completed current-day
   gate remains false after the persisted date changes to an old date, until
   explicit provider invalidation. This reproduces absence of a settings/date
   signal, not the passage of real midnight. Code inspection independently
   confirms no midnight/resume trigger for this provider. Add a date/lifecycle
   signal when implementing the recommended flow.
4. **Register loading/error recovery defect is reproduced in the actual widget.**
   With a cash-session stream still unresolved, `DailyGate` offers an enabled
   Open Register action. A mocked repository throws `session_already_open`
   (the actual repository's duplicate guard error); invoking the actual button
   callback propagates that error and leaves the action disabled/busy.
   This is an isolated UI test, not a production register mutation. Await a
   resolved session, catch open errors and restore retryable state in `finally`.

The widget harness initially omitted the app theme and failed during rendering;
after supplying the actual theme, all four diagnostics and the added permission
and failure-state assertions passed. The theme failure was a test setup issue,
not an app defect. No app source changed and no production staff/profile/till
was modified during these probes.

### Owner account handoff and auth-loss diagnostics (2026-10-14)

Two further diagnostic cases pass; these raise the priority of role persistence
above cosmetic daily-entry changes:

1. **License recomputation undoes Owner-account Staff handoff.** The actual
   `LicenseController` loads a shop license with mocked authenticated Owner
   identity. A named cashier is selected through the actual staff controller,
   persisting local role `staff`. Calling actual `recomputeExpiry()` changes
   the stored role back to `owner`, while the cashier ID remains selected.
   `_apply` calls `setStaffRole` on every matching authenticated account
   recomputation. Production triggers include a one-minute expiry timer,
   lifecycle resume and auth-state events. Real Owner auth plus local Owner
   mode opens owner capabilities, so this defeats the intended shared-phone
   PIN lockdown. The test uses mocked account metadata and no production
   credentials; it verifies the real persistence path, not a timed live-phone
   incident. Restore backend role on account/shop attachment, not every plan
   recheck; maintain explicit local handoff independently.
2. **Invited staff's local Owner selection can survive auth disappearance.**
   With synthetic backend role `staff` and a valid already-set Owner PIN,
   `switchRole('owner')` succeeds and persists local Owner. Effective role
   remains staff while the backend session exists. When the simulated backend
   role becomes null, actual `effectiveRoleProvider` resolves Owner. The daily
   gate can expose Owner selection; this case requires the valid Owner PIN,
   and the UI blocks creating that PIN as staff when none exists. It is not
   a PIN-free privilege bypass. Normal explicit staff signout reasserts local
   Staff, but losing auth outside that flow differs. Enforce invited-staff
   role constraints in the controller as well as visible screens, and persist
   account provenance separately from local handoff.

The temporary account/cache suite now passes four cases; the lifecycle suite
passes five cases. Only the two new cases were added in this follow-up; other
cases were rerun because their test fixtures were updated. Per-shop database
files are enabled in current app code, so no cross-shop PIN/permission leak is
claimed from inspection of ID-only local repository queries. Multi-shop guard
coverage remains required for any implementation change.

Recommended implementation order: prevent periodic Owner-role restoration,
preserve the invited-staff floor across auth loss, bind the actual cashier at
sale time, revoke inactive local identities, then address date and till loading
with retryable errors. Existing sales remain immutable throughout.

### Deployed permission-write boundary (2026-10-14)

Read-only production metadata queries show `staff_permissions` has a single
`shop_isolation` policy for ALL operations by `authenticated`, with both USING
and WITH CHECK equal to `shop_id = auth_shop_id()`. The role has INSERT, UPDATE
and DELETE table privileges. Its only non-internal trigger is the timestamp
trigger `touch_received_at`; no Owner-write trigger is present.

Migration 0072 explicitly describes a legacy workflow-only trust model where
all devices share a shop session. Current invited-email staff accounts are
separate authenticated identities, but this permission-write policy still only
checks the shop/current Premium device authority, not ownership. The app's
permission-edit screen correctly blocks effective Staff; that UI guard does
not prevent an authenticated staff client issuing its own request. The generic
`sync_force_apply` handler also includes `staff_permissions` in its allowed
tables and forwards writes as the authenticated user, so it relies on this RLS
policy rather than introducing a separate Owner restriction.

Three isolated PostgreSQL diagnostics pass using actual migrations 0094 and
0072, a temporary local staff account, a provisioned staff session, and table
grants matching the deployed metadata:

- Staff successfully inserts an own-shop capability row and changes its
  capability. The row can be used by the existing client grant resolution.
- The same staff request cannot write a different shop's permission row.
- An unprovisioned staff session cannot write an own-shop permission row.

This confirms a within-shop role authorization gap, not a cross-tenant breach
or anonymous access. It does not show this user exploited it or that any real
permission was altered without consent. Production inspection was SELECT-only;
all permission-write probes ran in a temporary local database that was removed
afterward. No real auth token was requested or used for a write test.

Repair priority now includes an Owner-only server write boundary for capability
administration, preserving staff's needed read access and trusted shop/device
checks. Check permission sync, backup restore and pending Owner-created outbox
rows after a device switches to staff; a rejected write must not wedge the queue
or discard valid Owner changes. Guard staff-profile mutation separately if PIN
identity and email linkage are intended to be trustworthy. Do not weaken shop
isolation or authenticate with a service-role client as a shortcut.

### Consolidated current-state verification requested by the owner

The owner asked to perform the remaining checks now and update the repair list,
not defer them until after repairs. Analyzer is clean and the full current
Flutter suite passes 1,076 tests. The existing selected backend suite passes 16
Deno tests, and the isolated account database suite passes 16 PostgreSQL tests.
The consolidated temporary probes pass 11 Flutter cases, 6 Deno handler cases
and 4 PostgreSQL cases. Passing these probes means current failure paths have
been reproduced, not fixed.

Four additional repair items are recorded in the consolidated list:

- Deployed staff-profile RLS/table privileges also allow same-shop staff to
  change PIN/email linkage. A real-policy local SQL test reproduces that change;
  production trigger metadata shows only the timestamp trigger.
- A legacy backup lacking envelope shop ID can restore shop-A rows into a
  shop-B database and delete shop-B's existing rows. Actual import in two
  in-memory databases reproduces this despite using the normal pending-outbox
  guard. Modern backups with a wrong explicit shop ID are correctly rejected.
- Two independent offline databases can open same-shop till sessions; merging
  the second session into the first database reproduces two open sessions and
  allocates one synthetic cash payment to both `expectedCash` calculations.
  No production sale or actual remote sync was created for this probe.
- Branch switching awaits unbounded session refresh at both refresh call sites;
  installed GoTrue request transport does not supply the missing timeout.
  This is verified source evidence, not a live transport stall reproduction.

Existing guards that passed include shop-scoped settings/database files,
pending/stuck-outbox transitions, modern wrong-shop backup refusal, denied
cross-tenant/unprovisioned writes, banned membership and device-release checks.
These passing paths are not new repair items.

Device discovery found the wireless iPhone, but no direct installed-iPhone UI
control is available in the task tools. It was not reinstalled/restarted or
made to open a real till, make a sale, change account or change its clock. Real
physical offline/midnight/receipt interactions remain unverified; current code
was exercised now through the isolated probes. No app/backend change or
production business-data mutation occurred.

Priorities after recovery: verify cashier stamping on one real intended sale,
repeat identity only for deliberate shared-device handoff, distinguish pending
Premium verification from Free, and handle cash-session loading/date/resume
independently from the once-per-day login marker. Do not create a fake sale or
open/close a real cash session merely to run this review.

- Identify the affected staff account/shop and device, without collecting its
  password. Inspect the deployed refresh result, subscription plan/expiry,
  active device binding, session shop/role and receipt identity. Do not print
  tokens, private signing material or service-role credentials.
- Reproduce first on a clean staff device, then a device changing from owner
  to staff in the same shop, with a failed refresh and an existing paid cache.
- Cover account changes with stale active staff, unlinked and duplicate email
  profiles, denied capabilities, signout, revocation and a full device roster.
- Cover roster-loading and cash-loading races, two simultaneous open actions,
  prior-day unclosed till, same-day close/reopen, midnight/resume, offline
  access and two shops on one device.
- Once implementation is requested, add meaningful regressions, perform the
  project ripple-effect checks, run analyze and full Flutter tests, update the
  changelog, and follow the deployment workflow for any app/backend changes.

Release follow-up: final reviewed build installed successfully on the owner iPhone
using the native installer. Launch check is waiting for the phone to be unlocked;
iOS explicitly reported Locked. Final analyzer is clean and 1,102 tests pass.
No commit or production business-data mutation was performed.
