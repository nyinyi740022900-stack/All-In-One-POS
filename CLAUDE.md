# All In One POS — project guide for Claude

Rebranded from GoldPOSMM 2026-08-16 — bundle ID `com.allinonepos.app`, web
projects `allinonepos-{admin,shop,invoices,legal}.vercel.app`. If you see
"GoldPOSMM"/"goldposmm-*"/`com.mmpos.*` anywhere outside a historical
`PROJECT_SPEC.md` changelog entry, it's stale and should be fixed.

Offline-first POS + license SaaS for Myanmar SMEs. **Flutter** app (iOS/Android)
+ **Flutter Web** admin console + **Supabase** (Postgres/Auth/Edge Functions).
Two languages everywhere: English + Myanmar.

## Stack & conventions
- **State:** Riverpod. **Routing:** go_router (`StatefulShellRoute`, **5 tabs**:
  Sell, Inventory, Orders, Analytics, Settings). The **Orders** destination is a
  hub with two sub-tabs — Orders (pre-sale social orders) and Invoices (the
  completed-sale ledger) — served by ONE `StatefulShellBranch` carrying two
  routes, `/orders` and `/invoices`, so both URLs and their deep links still
  resolve to the right sub-tab. Analytics is `ownerOnly` (hidden in Staff mode,
  giving 4 tabs); Settings always stays visible as the PIN escape hatch.
- **Local DB:** Drift (SQLite) — offline source of truth. **Cloud:** Supabase.
- **Structure:** feature-first under `lib/features/<name>/` (screen + providers +
  repository). Shared: `lib/core`, `lib/data` (local db, repositories, sync),
  `lib/domain`. Admin web is a separate entry point: `lib/admin/` (built with
  `-t lib/admin/admin_main.dart`, tree-shaken out of the mobile app).
- **Money** is `int` kyat (no cents). Use the `Money` value object.
- **Pure logic** (analytics, credit aggregation, license status, receipt
  formatting) lives in plain Dart classes with unit tests — keep it that way.

## ⚠️ Before shipping a change: ripple-effect check (do NOT skip)
`flutter analyze` clean + all tests passing does NOT mean a change is bug-free
— several real bugs have shipped this way (a table's derived balance not
watching a new column that affects it; a device-global settings key that
should have been per-shop; a provider missing a watch on a table it reads).
Unit tests here only cover **pure logic**; they cannot catch a Riverpod
provider silently going stale or a settings key bleeding across shops/tenants.
Before calling a change done:
1. **Grep every reader of a table/column you added or changed** (`grep -rn
   '<table_or_column>' lib`) and check each call site's semantics still hold
   — especially any other feature's derived total/balance that folds over the
   same table (e.g. adding `Expenses.accountId` should have triggered a check
   of Cash Register's `computeExpectedCash`, not just Payment Accounts).
2. **If you added a `FutureProvider`/derived value that depends on a table,
   confirm it `ref.watch()`s an invalidation signal for every table it
   reads** — not just the "obvious" one. Missing this makes the UI silently
   stale instead of throwing, so it won't surface as a test failure or an
   analyzer error.
3. **If you added a `SettingsRepository` key, ask: does this value belong to
   the device, or to the currently-active shop?** A device can switch shops
   (`BranchRepository.switchBranch`) without `wipeSyncedData()` touching
   `AppSettings` — a key that should be per-shop but isn't a fixed global key
   will silently bleed across shops. When in doubt, key it by `shopId` (see
   `SettingsRepository._shopKey`).
4. **Test the multi-shop case, not just the single-shop case**, for any
   repository/settings change that could plausibly differ per shop — see
   `settings_repository_test.dart` for the pattern (two shop ids, assert
   neither leaks into the other).

## ⚠️ Adding a synced table (do ALL of these — easy to miss a step)
1. `lib/data/local/tables.dart` — new table `with SyncColumns`.
2. `lib/data/local/database.dart` — register in `@DriftDatabase`, bump
   `schemaVersion`, add an `onUpgrade` `addColumn`/`createTable` branch.
3. `dart run build_runner build` (regenerates `database.g.dart`).
4. `lib/data/sync/sync_mappers.dart` — add a `SyncTableDef` (toRemote +
   upsertLocal with last-write-wins) and register it in `syncTables`.
5. `supabase/migrations/00NN_*.sql` — create the table **with RLS**:
   `enable row level security` + a `shop_isolation` policy
   (`shop_id = auth_shop_id()`). NOT dev-open. (See the 0012 lesson below.)
6. If it holds a counter (like stock): sync **movement deltas append-only**,
   never absolute quantities with LWW (LWW loses concurrent updates).
7. Run the **ripple-effect check** below — a new column especially tends to
   silently invalidate an existing feature's assumptions (e.g. "every
   Expense is paid from the till") rather than break loudly.

## Sync model (don't break these invariants)
- **Outbox pattern:** every mutation writes local + enqueues to `outbox`; the
  sync engine drains it. The push loop **isolates failures** — one bad row must
  not wedge the queue (regression-tested in `sync_engine_test.dart`).
- **Sales are append-only** (immutable ledger) — never update a sale.
- Every row has a client-generated UUID (idempotent retries).
- **Multi-tenant:** RLS `shop_isolation` on every synced table; users get the
  `shop_id` JWT claim via `activate` (keys) or `start_trial` (trials). Applying
  a migration that only drops `dev_open` without (re)creating `shop_isolation`
  will make tables default-deny and break the app — always recreate it.

## i18n (parity is enforced by a test)
- Add every string to BOTH `lib/l10n/app_en.arb` AND `lib/l10n/app_my.arb`,
  then `flutter gen-l10n`. `i18n_parity_test.dart` fails on missing keys.

## Licensing
- Online: key `activate` (device-bound, one device per key) + subscribe
  requests + auto re-verify. Offline: **Ed25519 signed tokens** (`MMPOS1.`
  prefix) verified locally against the public key in `offline_license.dart`
  (private key is a Supabase secret, NEVER in the repo). Free 2-month trial is
  server-tracked per device.

## Security — hard rules
- **NEVER commit** `env.local.json`, private keys (hex seeds), or the Supabase
  service-role key. Anon key is fine (RLS enforces access).
- New tables/functions must enforce shop isolation / admin-role checks.
- Edge Functions hold the service role; the client only ever has the anon key.

## Workflow
- Before any build: `flutter analyze` (clean) + `flutter test` (all pass).
- **Owner rule (2026-08-22): once you START a fix, do not stop until it is
  fully done** — code + `analyze` + full `flutter test` + changelog entry,
  then deploy to device if it's an app change. Report only after all of that,
  and end with a written "what's next / what to verify" list.
- **Before marking a feature done, run the ripple-effect check above** —
  don't wait for the user to request a separate audit pass to catch a stale
  provider or a device-global key that should've been per-shop.
- **Reflect every change in `PROJECT_SPEC.md` §12 changelog** (same change-set).
- Deploy: see the `deploy` skill (db push → functions deploy → admin web to
  Vercel → build to device). Test migrations on staging before prod.
- Build to the phone: `flutter run --release -d <ios-device> --dart-define-from-file=env.local.json`.
