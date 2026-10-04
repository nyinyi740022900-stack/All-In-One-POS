# Account Premium Implementation Plan

> **For agentic workers:** Use subagent-driven-development to implement and review each owned module. Preserve concurrent changes; do not stage or revert another worker's files.

**Goal:** Ship account-only Premium with one subscription per shop, explicit account trial, three devices, safe offline lapse and the approved Free feature set.
**Architecture:** Add cloud-only subscription/device/trial authority while retaining legacy licence rows as migration evidence. Keep existing `activate` endpoint name but retire key actions and refresh through authenticated membership. Migrate client capability gates and all billing consumers together.
**Tech Stack:** Flutter/Riverpod/Drift, Supabase Postgres/Auth, Deno Edge Functions.
**Spec:** `docs/superpowers/specs/2026-10-03-account-premium-design.md` (approved 2026-10-03).

## Global constraints

- Free remains account-optional; Premium requires an authenticated shop member and verified bound receipt.
- Myanmar 20,000 MMK monthly / 200,000 MMK yearly, one owner trial of two calendar months, three concurrent devices per shop, fourteen-day grace.
- No exposed licence keys, provisioning QR keys or Online/Offline pricing choices. Legacy keys are migration evidence only.
- All additions to UI copy in both ARBs; root coordinates ARB writes and generation.
- No delete/rewrite of existing ledger rows, outbox, unrelated edits or shop-local files.
- Backend writes service-role-only; ownership is from trusted metadata/validated memberships, never editable user metadata.
- Tests first, then implementation. Full analyze/test and relevant Deno checks, staging rehearsal, ripple audit and release device smoke check before calling shipped.

## Shared API contracts

`POST activate` keeps `signup_shop`, `create_shop_login` (trusted legacy migration only), `start_trial`, `refresh_account_license`, `release_device`, `list_devices`, branch/account/staff actions. Key `activate`, `link_branch`, `request_device_slot`, anonymous trial and `set_tier` return explicit retired-path failures. Signup returns `plan: free`; trial requires a real owner. Device-limit errors use `device_limit_reached`; errors for explicit removal use `device_released`, `shop_archived`, `membership_revoked`. Network errors never downgrade verified Premium.

Successful subscription replies carry `{ok, shop_id, plan, expires_at, activated_at, device_id, user_id, revision, entitlement, server_time}`. Free uses an ISO expiry sentinel and no signed Premium proof. Keep harmless `key: SIGNUP`/`tier: online` response compatibility temporarily for old Dart model consumers, but no activation secret is accepted or displayed. New bound receipts use the existing `AIOE1.` envelope with payload `v: 2`, `shop_id`, `user_id`, `device_id`, `plan`, `exp`, `iat`, `revision`. Unknown versions, missing binding or identity mismatches fail closed.

Backend authority migrations numbered 0094; billing adjunct migration numbered 0095. Authority produces service-role RPC `renew_shop_subscription(p_shop_id text, p_months int, p_payment_id text)` returning JSON `{expires_at, duplicate}` atomically. Billing uses unique stable IDs per request/webhook/admin operation. `shop_subscriptions` contains `shop_id, plan, expires_at, activated_at, revision, is_archived`. `shop_devices` includes shop/device ID, user ID, released timestamp and last activity. Billing must communicate any needed schema amendments to authority owner.

## Task 1: Server authority and migration

**Own:** `supabase/migrations/0094_account_premium.sql`, `supabase/functions/activate/`, `_shared/entitlement.ts`, new `_shared/account_premium.ts`, backend tests and isolated SQL fixture tests.

- [x] Write/run failing SQL fixtures for trial reuse, three-slot concurrent allocation, denied cross-shop access and idempotent renewal; add Deno tests for bound receipt input/retired key paths.
- [x] Backfill subscriptions/devices/trial claims, restrict membership writes and provide a read-only preflight report for ambiguous owners/paid allowances.
- [x] Implement atomic register/release/trial/renewal RPCs. For renewal: `base = oldExpiry >= now - 14 days ? oldExpiry : now`, plan promotion and revision bump inside the transaction.
- [x] Route authenticated actions through authority; preserve valid Free signup/promotion and branch/account recovery. No new branch auto-trial.
- [x] Test actual functions/RPCs, run Deno checks, report interfaces and migration concerns to root.

## Task 2: Account client and entitlement lifecycle

**Own:** `lib/features/license/`, `lib/features/account/`, `lib/features/onboarding/`, `lib/features/support/vendor_config.dart`, `lib/invoices_web/`, associated tests. Do not edit ARBs/generated files; send root new key/value pairs.

- [x] First fail tests proving bound receipt mismatch, online rejection versus timeout, local expiry and renew-after-Free identity preservation.
- [x] Parse v2 receipts and persist accepted revision with per-shop scope; root adds settings keys/guard classification if required.
- [x] Replace key/trial/provisioning and tier UI with sign-in, explicit trial and owner device list/release. Trial signup stays Free and existing local identity promotion remains recoverable.
- [x] Refresh signed-in shop by account even after lapse; maintain a local expiry timer/resume hook and cancel async work on dispose/shop transition.
- [x] Migrate invoice-web login and enforce failed claims rather than fail-open. Staff never inherit owner rights on sign-out/lapse.
- [x] Run targeted tests; report new i18n needs and ripple dependencies.

## Task 3: Billing, admin and storefront server

**Own:** `lib/admin/`, `lib/storefront/`, `supabase/functions/admin/`, `supabase/functions/storefront/`, `supabase/functions/lemonsqueezy-webhook/`, migration 0095 and their tests. Root owns ARBs.

- [x] Fail real backend tests for anonymous device-ID purchase, duplicate fulfilment and new storefront orders after lapse.
- [x] Authenticate account renewal; bind selected shop through verified owner membership; server chooses amount and plan.
- [x] Use authority renewal RPC with payment identity; keep paid-request retry result and duplicate webhook safe.
- [x] Remove keys, tier pricing, extra-slot fees and key provisioning from admin/renew/invoice receipts. Use subscription/device authority for shop listing/archive/extend.
- [x] Gate new public orders on current shop Premium; retain previous orders and customer invoice access.
- [x] Verify relevant Deno functions and client tests; report i18n requests and SQL fixtures.

## Task 4: Free capabilities, sync, settings and integration (root)

**Own:** analytics/accounting hub gates, Settings wiring, `lib/data/sync/`, payable/purchasing recovery, settings repository scope, ARBs/generated translations, docs, CI integration tests.

- [x] Fail widget tests where a Free owner must see Sales/Collected/Owed but not profit; retain owner-only authorization.
- [x] Open basic analytics and keep advanced report routes/exports gated; allow raw data export and existing-obligation repayment.
- [x] Pause cloud sync/realtime on missing/lapsed Premium without clearing outbox; watch license state so verified renewal restarts safely.
- [x] Consolidate i18n batches, generate translations, update scope/invalidation guards and affected widget fixtures.
- [x] Review Tasks 1–3 for spec/security/quality and fix integration failures.

## Task 5: Verification and delivery

- [x] Read-only live preflight; do not expose secrets or modify cloud state until migration rehearsal and integrated tests pass.
- [ ] Run new SQL integration fixtures against isolated Postgres plus staging when available. Never use production to discover a migration failure.
- [x] `flutter analyze`, full `flutter test`, all changed Edge Function `deno check`; ripple every reader of altered subscription/device/licence/settings semantics.
- [x] Update PROJECT_SPEC sections 6/12 and stale AGENTS/CLAUDE licensing docs. Record exact verified limitations.
- [ ] Deploy verified migrations/functions/web companions and build/install release on phone per deploy skill; diagnose any external limitation and complete unaffected steps.
- [ ] Smoke test owner/staff, local Free promotion, explicit trial, fourth-device refusal, offline expiry, lapse obligations and renewal. Report outcome with what's next/what to verify.

## Progress and rulings

- Work on `codex/account-premium` in the existing checkout to preserve the current approved but uncommitted UI baseline. A fresh default-branch worktree would omit those changes; no stash/reset is authorized or needed.
- The current checkout has existing UI modifications; tasks own non-overlapping modules and root integrates shared files. No blanket staging or destructive clean.
- Spec approved for execution by owner on 2026-10-03. Detailed device/lapse policies are part of that approval.

## Execution report — 2026-10-03

Implemented tasks1–4 and completed independent spec/security review. All identified P1/P2 defects were resolved and verified, including silent background shop switching, staff authorization after session loss in a newly reopened database, atomic trial/device allocation, explicit owner Free-device replacement, and in-flight sync cancellation without outbox quarantine.

Verification: analyzer clean, all947 Flutter tests pass,52 isolated PostgreSQL tests pass,17 Deno signature/handler tests pass, all Edge Function type checks pass. SQL fixtures run against disposable local PostgreSQL instances; this is not a claim of staging or live rehearsal. Provider invalidation, settings-scope and English/Myanmar parity guards are included in the full suite.

Production read-only preflight:10 shops/11 legacy licence rows; one shop has two real owner candidates, one branch link references a missing owner. No active purchased extra allowances or over-capacity bound devices. No pending legacy billing requests and no recorded gateway events. International gateway configuration exists but LEMONSQUEEZY_API_KEY and LEMONSQUEEZY_STORE_ID secret names are absent; signing/webhook secret names exist. No credential values were displayed.

Live rollout remains dependent on human-verified owner resolution and a staging project/reference. Migration0094 deliberately aborts unresolved ownership. Do not choose an owner from timestamps, email spelling or a public device ID. Retain orphan shop records pending recovery; only remove an orphan navigation link with explicit authorization. After resolving owners, rerun the read-only preflight, rehearse0094/0095 plus session RLS on staging, configure server gateway secrets through the secure dashboard, then deploy coordinated functions and the three web targets before installing the new phone app. Verify processor subscriptions separately before enabling gateway events; absence of local event rows is not proof that none exist at the processor.

No live database/function/web/device deployment occurred. Final release builds succeeded for admin, shop and invoices through tool/build_web.sh (target-specific page heads checked), and a signed iPhone build succeeded: build/ios/iphoneos/Runner.app,42.6MB. Pre-build Podfile.lock was restored; pre-existing Package.resolved removals and unrelated approved UI edits remain. No phone install or live-browser smoke test is claimed.

Accessible Supabase projects were checked read-only. Only the production POS project and an unrelated project are listed; no POS staging project was identified. No unrelated project was modified or treated as staging.

Next verification after authorized cutover: owner signup/local promotion; explicit first-shop trial; concurrent fourth-device refusal; staff session loss/offline lapse without owner elevation; Free replacement by releasing old device and restoring local backup; retained supplier/old-order obligations; idempotent renewal; actual signed receipt on the paired phone and provisioned invoice browser.

## Owner-authorized cleanup - 2026-10-04

Owner explicitly selected shops only: MM SHOP and Home deleted server-side, retaining both owner accounts. Count-only preflight found2license rows,3branch links and4payment-account rows; no business-ledger rows or shop-prefix storage objects. Scoped transaction checked expected counts, preserved all other-shop counts, unlinked only target shop_id metadata, and retained131Auth users. Independent post-cleanup preflight now reports8shops/9legacy rows and zero ownership/capacity/paid-allowance blockers. Earlier ownership questions are resolved by this deletion instruction. No full production-data export occurred: automatic review rejected that backup approach, and count-only verification was used instead. Premium schema/functions/web/phone rollout remains pending staging and the separate international payment setup plan.

Before production migration: preserve historical trial-consumption evidence for the deleted MM SHOP and its two previously trusted owner accounts. The pre-delete read-only report recorded historical_trial=true. Extend trusted legacy trial backfill with an audited mapping and SQL regression so retaining an account while deleting its shop cannot reset once-owner eligibility. This is a pending cutover requirement, not a claim that the current migration already handles purged history.


## Phone-first delivery and store policy hardening - 2026-10-04

Owner authorized phone-first installation, deferring international API setup. Analyzer clean and952 Flutter tests passed before signed42.6MB build. CoreDevice install and launch succeeded on iPhone17ProMax; no backend/web deployment. Owner development binary uses COMMERCE_UI=true and must never be submitted to a store. Subsequent store-only neutral copy and reviewer/listing corrections verified with analyzer and960 full tests. Rendered store tests cover Free/active/grace/expired in English/Myanmar; these are not an approval guarantee. Apple3.1.3(b) alone requires equivalent IAP; evaluate3.1.3(f) against the actual service or implement native billing before submission. Live reviewer account and physical matrix remain pending. UI chat owns a reported DailyGate Continue investigation; avoid duplicate device delivery while it is active.


## Premium admin audit - 2026-10-04

Implemented: removed redundant Licensing navigation and unused public store-slug/Buy-Now editors; retained Shops/Inbox/Payments/Settings. Removed dead cached gateway fields while preserving configured monthly/yearly variant consumption. Added English/Myanmar public-config warning/labels and ownerless renewal guidance. Backend validates positive numeric variant IDs before public writes and returns only editable public configuration. SQL renewal now refuses missing/anonymous/banned owner authority. Audited deleted-MM-SHOP trial consumption is seeded for the two retained accounts (existing claims preserved; no shop recreated). Admin status now distinguishes exact active/grace/expired boundaries using the same shared entitlement logic.

Verification: 29 focused Flutter admin/vendor/i18n tests, 58 isolated account/billing SQL tests, 20 Deno handler/status tests passed; five touched Edge Functions type-check. Full integrated Flutter run failed loading concurrently edited social_auth_widgets_test.dart (canRecoverDevice contract mismatch); shared analysis still had 12 social-auth lint findings. Do not build/deploy while these gates remain red. No production migration/function/web/app deployment by this audit. Staging project reference requested from owner and still pending. International test-mode implementation, product/variant/provider webhook verification and coordinated rollout remain pending.
