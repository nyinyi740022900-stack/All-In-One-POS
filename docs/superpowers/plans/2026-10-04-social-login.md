# Google and Apple Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native social login, safe existing-account linkage and first-shop setup, with social account deletion and existing email login retained.
**Architecture:** Supabase validates native provider credentials; shared authenticated-account attachment owns local DB/outbox/device transitions. Server-only first-shop provisioning remains authoritative and idempotent. UI reuses a common social-flow helper.
**Tech Stack:** Flutter/Riverpod, google_sign_in 7.2, sign_in_with_apple 8.2, Supabase Auth/Edge Functions/Postgres.
**Spec:** docs/superpowers/specs/2026-10-04-social-login-design.md

## Global Constraints

- Money is int kyat; no changes to sale ledger, outbox, PIN permissions, pricing, or trial rules.
- English + Myanmar parity; no provider credentials in git or client secrets in the app.
- Use the approved shared branch and preserve all concurrent edits. No blanket commits, backend deploys or migration cutover in a worker.
- Providers stay hidden until configured. Google OAuth is not yet configured by owner.
- Full checks, ripple review and changelog before device delivery; real provider login must be verified after setup.

### Task 1: Native provider authentication
**Ownership:** lib/features/account/social_auth.dart, lib/core/env.dart, pubspec.yaml/lock, iOS/Android provider configuration, test/social_auth_test.dart, docs/social_login_setup.md.
**Interfaces:** Exact service/proof/failure/provider signatures in spec. Google native initialization uses Web client ID as serverClientId; iOS uses its platform client ID and reversed URL scheme. Apple hashes a random raw nonce. Sign-in and link invoke Supabase; reauthentication returns tokens without replacing app session.
- [ ] Test cancellation/unavailable configuration/proof encoding/platform visibility before implementation.
- [ ] Implement service with injectable token acquisition for tests and bounded network waits.
- [ ] Fetch verified package versions, document precise setup and keep absent setup disabled.
- [ ] Run focused tests and send review package; do not edit repository/UI/backend files.

### Task 2: Authoritative social provisioning and deletion
**Ownership:** supabase/functions/activate/index.ts and new social handler/helper/tests, migration after existing highest version, staging SQL tests.
**Interfaces:** prepare_social_account, signup_social_shop and delete_account social proof described in spec. Existing signup/password deletion stay compatible.
- [ ] Add failing tests for existing owner, existing staff, first account, repeated signup, mismatched reauth user and invalid proof.
- [ ] Add a server-only RPC with a per-user advisory transaction lock to provision first Free shop idempotently, refusing existing staff/archived identities.
- [ ] Verify social reauth proof with Supabase Auth and same authenticated user; never trust decoded claims before signature validation.
- [ ] Run Deno checks/tests; provide migration staging verification requirements. Do not deploy.

### Task 3: App attachment and safe transitions
**Ownership:** lib/features/account/account_repository.dart, account_providers.dart, focused repository tests.
**Interfaces:** AccountActionResult.needsShopName; methods/getters in spec.
- [ ] Extract the existing post-password-auth attachment path so social login uses the same confirmation/outbox/device binding.
- [ ] Test new-user shop-name result, same-shop attachment, different-shop confirmation, provider cancellation and linking.
- [ ] Implement social first-shop signup through server action, refresh JWT, promote local Free data before saving new license, then attach device.
- [ ] Implement same-user identity link and social deletion; preserve legacy password deletion and local role floors.

### Task 4: Shared UI and localization
**Ownership:** lib/features/account/social_auth_widgets.dart, shop_login_screen.dart, onboarding_flow.dart, daily_gate.dart, ARBs/generated localization, focused social UI tests.
**Interfaces:** Consumes AccountRepository methods/getters and SocialAuthProvider. Shared helper prompts shop name/real-shop confirmation and returns AccountActionResult or null on cancel. Screens apply result license and refresh role/session/sync identically to password paths.
- [ ] Test absent setup renders no social buttons; configured provider choices, busy state, cancellation, name prompt and long Myanmar/large text.
- [ ] Add buttons to all three entry points; signed-in account offers explicit identity linking.
- [ ] Social-only account deletion requests supported linked-provider reauthentication rather than a nonexistent password.
- [ ] Add all strings in both ARBs and regenerate. Preserve daily-entry fixes and existing password workflows.

### Task 5: Review and delivery
- [ ] Independent spec/quality review of each task, then integration review.
- [ ] Ripple-check auth listeners, session/shop binding, staff permissions, first Free promotion, device limits, trial identity, and both account-deletion methods.
- [ ] Analyze, full Flutter tests, Deno tests/checks; update PROJECT_SPEC.
- [ ] Verify staging compatibility before any backend cutover. Install verified client if safe and document remaining real-provider setup/retest.

## Execution ledger
- Ruling: continue on existing codex/account-premium shared workspace — user authorized app changes here and current fixes must be preserved.
- Ruling: do not ask again for approved design/execution method; execute with disjoint workers and review.
- Prerequisite: owner confirmed no Google OAuth setup; credential-dependent live login cannot yet be claimed.

- Review: closed alternate authenticated signup_shop Staff promotion and duplicate first-shop creation; no production migration applied.
- Review: unfinished social flows abandon temporary auth even after widget disposal; successful attachments and owner device recovery are retained.
- Ripple audit: new SQL authority/proof table is server-only (no client derived provider), and configuration uses build defines rather than SettingsRepository keys. Existing auth event watches update role/email/session; UI linking watches events. Multi-shop repository regression rewrites only local Free rows, retains other-shop rows and verifies outbox enqueue/promotion marker cleanup.
- Live prerequisite: linked production ends at0093; only production and unrelated project available, no POS staging identified. Do not apply0094–0096 without staging and coordinated Premium cutover. Google/Apple disabled in current env.
