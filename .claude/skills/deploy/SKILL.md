---
name: deploy
description: Deploy GoldPOSMM — apply Supabase migrations + Edge Functions, redeploy the admin web to Vercel, and install the app on the iPhone. Use when shipping backend or app changes. Includes the exact commands, ordering, and known caveats.
---

# Deploy GoldPOSMM

Always `flutter analyze` (clean) + `flutter test` (all pass) FIRST.

Live project: `gnikispsurwrmkspuisj` (must be `supabase link`ed as the
GoldPOSMM-owning account). Admin web: Vercel project `goldposmm-admin`, scope
`nyi-nyi-s-projects1`. iPhone id: `00008150-001A44C41E08401C`.

## 1. Supabase migrations
```bash
supabase migration list            # see what's pending
supabase db push                   # apply new migrations
```
⚠️ For an RLS-changing migration, verify on a fresh anon session BEFORE trusting
it: a matching-shop write → 201, a cross-shop write → 403, a no-claim write →
403. (A migration that drops `dev_open` MUST re-create `shop_isolation` on all 9
synced tables — otherwise core tables go default-deny. See the 0012 lesson.)

## 2. Edge Functions
```bash
supabase functions deploy admin --project-ref gnikispsurwrmkspuisj
supabase functions deploy activate --project-ref gnikispsurwrmkspuisj
supabase functions deploy start_trial --project-ref gnikispsurwrmkspuisj
supabase functions deploy storefront --project-ref gnikispsurwrmkspuisj
supabase functions deploy sync_force_apply --project-ref gnikispsurwrmkspuisj
```
Secrets (rarely): `supabase secrets set NAME=value --project-ref ...`.

`sync_force_apply` — authenticated shop-scoped outbox heal (service role
upsert after JWT `shop_id` check). Required for self-healing sync (#93);
without it, quarantined rows stay held until the next deploy.

## 3. Admin web → Vercel
```bash
flutter build web -t lib/admin/admin_main.dart --dart-define-from-file=env.local.json --no-web-resources-cdn
# stage build/web/ + a vercel.json SPA-fallback, then:
#   { "routes": [ { "handle": "filesystem" }, { "src": "/.*", "dest": "/index.html" } ] }
cd build/web && vercel deploy --prod --yes --scope nyi-nyi-s-projects1
```
Stable URL: https://goldposmm-admin.vercel.app (use this; the per-deployment URL
is SSO-gated).

## 3b. Storefront web → Vercel
Same build/deploy shape as above, different target + project:
```bash
flutter build web -t lib/storefront/storefront_main.dart --dart-define-from-file=env.local.json --no-web-resources-cdn
cd build/web && vercel link --yes --project goldposmm-shop --scope nyi-nyi-s-projects1
vercel deploy --prod --yes --scope nyi-nyi-s-projects1
```
Stable URL: https://goldposmm-shop.vercel.app.

## 3c. Invoices Web companion → Vercel
Read-only "view & print own invoices" companion for a shop's computer (Phase 1
of computer/tablet support — see PROJECT_SPEC §12). Same shape again:
```bash
flutter build web -t lib/invoices_web/invoices_web_main.dart --dart-define-from-file=env.local.json --no-web-resources-cdn
cd build/web && vercel link --yes --project goldposmm-invoices --scope nyi-nyi-s-projects1
vercel deploy --prod --yes --scope nyi-nyi-s-projects1
```
Stable URL: https://goldposmm-invoices.vercel.app. No backend changes ship with
this one — it activates via the existing `activate` function and reads
`sales`/`sale_items`/`storefronts` directly, so redeploying it is web-build-only.

## 3d. Desktop — Windows POS (macOS deferred)
Full POS on **Windows** (Sell/Inventory/Orders + native Drift). macOS
scaffolding exists but is **out of scope** (blank-window; not prioritized).

**Build gate (from this Mac):** GitHub Actions
[`.github/workflows/windows_desktop.yml`](../../.github/workflows/windows_desktop.yml)
— `windows-latest`, uploads `GoldPOSMM-windows-<sha>`. Optional secrets:
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SENTRY_DSN`.

Docs: [`docs/windows/`](../../docs/windows/). Human smoke on a Windows PC
only after CI is green (`docs/windows/SMOKE.md`).

```bash
# On a Windows machine only (not on macOS):
flutter build windows --release --dart-define-from-file=env.local.json
```

Invoices-only on any computer: Phase 1 web companion
`https://goldposmm-invoices.vercel.app` (no local DB).

## 4. App → iPhone (wireless)
```bash
flutter run --release -d 00008150-001A44C41E08401C --dart-define-from-file=env.local.json
```
Run in the background; wait for "Flutter run key commands", then kill the
process (app stays installed). If it fails with "Could not run … on iPhone",
the phone is locked/asleep OR a native plugin failed to compile — check the log
for `Swift Compiler Error` before assuming it's the device.

## 5. App Store / TestFlight (IPA)
Kit: `docs/app_store/` (listing copy, privacy nutrition, review notes, smoke
checklist). Privacy Policy (live): https://goldposmm-legal.vercel.app  
Redeploy policy HTML:
```bash
cd docs/app_store/privacy && vercel deploy --prod --yes --scope nyi-nyi-s-projects1
```

Bump `pubspec.yaml` build (`+N`) before every upload — see
`docs/app_store/VERSIONING.md`.

```bash
# 1) Archive + export (needs Apple Distribution via Automatic signing / team F8KLK8L5SY)
#    If export fails (“No signing certificate iOS Distribution”), see
#    docs/app_store/DISTRIBUTION_SIGNING.md — archive is still at
#    build/ios/archive/Runner.xcarchive for Xcode Organizer upload.
flutter build ipa --release --dart-define-from-file=env.local.json \
  --export-options-plist=ios/ExportOptions.plist

# 2) Upload to App Store Connect (requires App Store Connect API key — ACCOUNT.md)
export APP_STORE_CONNECT_KEY_ID=…
export APP_STORE_CONNECT_ISSUER_ID=…
export APP_STORE_CONNECT_KEY_PATH=$HOME/.appstoreconnect/private_keys/AuthKey_….p8
./tool/upload_ios_ipa.sh

# 3) TestFlight → Internal smoke (`docs/app_store/TESTFLIGHT_SMOKE.md`)
# 4) Listing + Submit (`LISTING.md`, `SUBMIT.md`) — first public release: Manual release
```

## 6. Play Store (AAB)
Kit: `docs/play_store/` (signing, listing, Data safety, internal test, submit).
Privacy Policy: https://goldposmm-legal.vercel.app  
Package: `com.mmpos.mm_pos` (do not change).

```bash
# 1) One-time: create upload keystore + android/key.properties
#    (see docs/play_store/SIGNING.md — never commit .jks / key.properties)

# 2) Bump pubspec build (+N), then:
flutter build appbundle --release --dart-define-from-file=env.local.json
# → build/app/outputs/bundle/release/app-release.aab

# 3) Play Console → Internal testing → upload AAB → smoke
#    (docs/play_store/INTERNAL_TEST.md)
# 4) Listing + Data safety + production
#    (LISTING.md, DATA_SAFETY.md, SUBMIT.md) — prefer staged rollout first
```

Without `android/key.properties`, release assemble/bundle **fails on purpose**
(no debug-key fallback).

## Notes
- The auto-mode safety classifier may still block prod writes even with the
  permission allow-rules; if so, hand the exact command to the user.
- Reflect the deploy in `PROJECT_SPEC.md` §12 + the `supabase-backend` memory.
