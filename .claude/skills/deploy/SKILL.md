---
name: deploy
description: Deploy All In One POS — apply Supabase migrations + Edge Functions, redeploy the admin web to Vercel, and install the app on the iPhone. Use when shipping backend or app changes. Includes the exact commands, ordering, and known caveats.
---

# Deploy All In One POS

Always `flutter analyze` (clean) + `flutter test` (all pass) FIRST.

Live project: `gnikispsurwrmkspuisj` (must be `supabase link`ed as the
All In One POS-owning account). Admin web: Vercel project `allinonepos-admin`,
scope `nyi-nyi-s-projects1`. iPhone id: `00008150-001A44C41E08401C`.

Rebranded from GoldPOSMM 2026-08-16 — bundle ID `com.mmpos.mmPos` /
`com.mmpos.mm_pos` → `com.allinonepos.app`, every `goldposmm-*.vercel.app`
project → `allinonepos-*.vercel.app` (old URLs are dead, not redirected).

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
supabase functions deploy storefront --project-ref gnikispsurwrmkspuisj
supabase functions deploy sync_force_apply --project-ref gnikispsurwrmkspuisj
```
Secrets (rarely): `supabase secrets set NAME=value --project-ref ...`.

`sync_force_apply` — authenticated shop-scoped outbox heal (service role
upsert after JWT `shop_id` check). Required for self-healing sync (#93);
without it, quarantined rows stay held until the next deploy.

## 3. Admin web → Vercel

Build the web targets with `tool/build_web.sh <target>`, never a bare
`flutter build web`. Flutter compiles all three entry points through the one
shared `web/index.html`, so a raw build ships the storefront's title,
description and og: tags on the admin console and the invoices viewer —
`MaterialApp.title` corrects the browser tab after boot, but a crawler or a
Viber/Messenger link preview only ever reads the static head. The script
builds and stamps the correct head in one step.

```bash
./tool/build_web.sh admin
# stage build/web/ + a vercel.json SPA-fallback, then:
#   { "routes": [ { "handle": "filesystem" }, { "src": "/.*", "dest": "/index.html" } ] }
cd build/web && vercel deploy --prod --yes --scope nyi-nyi-s-projects1
```
Stable URL: https://admin.allinonepos.app (use this; the per-deployment URL
is SSO-gated).

⚠️ **§3b/3c reuse the same `build/web/` directory for different Vercel
projects.** `vercel link` writes the target project into `build/web/.vercel/`,
which persists across rebuilds — if you `link` to `shop` then later `link` to
`invoices` in the same session, `build/web` is now linked to `invoices` even
after you rebuild it with `shop` content. Deploying without re-linking ships
the wrong build to the wrong live URL with a clean, misleading `"status":
"ok"` exit (caught live 2026-09-02, PROJECT_SPEC #286 — shipped `shop`'s
build to `invoices.allinonepos.app`). **Always run `vercel link --project
<name>` immediately before every `vercel deploy` in §3b/3c, even if you
already linked to that same project earlier in the session** — never assume
the existing link still matches. After any deploy in this shared directory,
verify the live page title (or another target-specific marker) before
trusting the deploy, not just the exit code.

## 3b. Storefront web → Vercel
Same build/deploy shape as above, different target + project:
```bash
./tool/build_web.sh shop
cd build/web && vercel link --yes --project allinonepos-shop --scope nyi-nyi-s-projects1
vercel deploy --prod --yes --scope nyi-nyi-s-projects1
```
Stable URL: https://shop.allinonepos.app.

## 3c. Invoices Web companion → Vercel
Read-only "view & print own invoices" companion for a shop's computer (Phase 1
of computer/tablet support — see PROJECT_SPEC §12). Same shape again:
```bash
./tool/build_web.sh invoices
cd build/web && vercel link --yes --project allinonepos-invoices --scope nyi-nyi-s-projects1
vercel deploy --prod --yes --scope nyi-nyi-s-projects1
```
Stable URL: https://invoices.allinonepos.app. No backend changes ship with
this one — it activates via the existing `activate` function and reads
`sales`/`sale_items`/`storefronts` directly, so redeploying it is web-build-only.

## 3d. Desktop — Windows POS (macOS deferred)
Full POS on **Windows** (Sell/Inventory/Orders + native Drift). macOS
scaffolding exists but is **out of scope** (blank-window; not prioritized).

**Build gate (from this Mac):** GitHub Actions
[`.github/workflows/windows_desktop.yml`](../../.github/workflows/windows_desktop.yml)
— `windows-latest`, uploads `AllInOnePOS-windows-<sha>`. Optional secrets:
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SENTRY_DSN`.

Docs: [`docs/windows/`](../../docs/windows/). Human smoke on a Windows PC
only after CI is green (`docs/windows/SMOKE.md`).

```bash
# On a Windows machine only (not on macOS):
flutter build windows --release --dart-define-from-file=env.local.json
```

Invoices-only on any computer: Phase 1 web companion
`https://invoices.allinonepos.app` (no local DB).

## ⚠️ `COMMERCE_UI` — get this right or the store build is a 3.1.1 violation
`lib/core/build_flags.dart`'s `kCommerceUiEnabled` **defaults to false**: no
prices, no Pay-online button, no Viber-to-buy card, no Refer & earn. That is
what makes an App Store / Play build compliant (guideline 3.1.3(b),
Multiplatform Services — see `docs/app_store/REVIEW_NOTES.md`).

- **Store builds (§5 IPA, §6 AAB): pass NOTHING.** The default is the correct,
  compliant value.
- **Direct-install APK / `flutter run` for the owner (§4): add
  `--dart-define=COMMERCE_UI=true`** to get the purchase UI back.
- **Never put `COMMERCE_UI` in `env.local.json`.** Every build below reads that
  file, store builds included — putting it there switches commerce back on in
  exactly the build that must not have it.

`flutter test` (no defines) runs `test/commerce_ui_gate_test.dart`, which fails
if the default is flipped or a purchase string reappears ungated.

## 4. App → iPhone (wireless)
```bash
flutter run --release -d 00008150-001A44C41E08401C --dart-define-from-file=env.local.json \
  --dart-define=COMMERCE_UI=true
```
Run in the background; wait for "Flutter run key commands", then kill the
process (app stays installed). If it fails with "Could not run … on iPhone",
the phone is locked/asleep OR a native plugin failed to compile — check the log
for `Swift Compiler Error` before assuming it's the device.

## 5. App Store / TestFlight (IPA)
Kit: `docs/app_store/` (listing copy, privacy nutrition, review notes, smoke
checklist). Privacy Policy (live): https://legal.allinonepos.app  
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
# No COMMERCE_UI define here — the false default is what keeps this build
# compliant. See the warning above §4.
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
Privacy Policy: https://legal.allinonepos.app  
Package: `com.allinonepos.app` (was `com.mmpos.mm_pos` before the 2026-08-16
rebrand — no Play upload has happened yet, so this is safe to have changed;
do not change again once a real upload exists).

```bash
# 1) One-time: create upload keystore + android/key.properties
#    (see docs/play_store/SIGNING.md — never commit .jks / key.properties)

# 2) Bump pubspec build (+N), then:
#    No COMMERCE_UI define — Play Billing has the same rule as Apple's 3.1.1,
#    so the store AAB ships commerce-free too. See the warning above §4.
flutter build appbundle --release --dart-define-from-file=env.local.json
# → build/app/outputs/bundle/release/app-release.aab

# 3) Play Console → Internal testing → upload AAB → smoke
#    (docs/play_store/INTERNAL_TEST.md)
# 4) Listing + Data safety + production
#    (LISTING.md, DATA_SAFETY.md, SUBMIT.md) — prefer staged rollout first
```

Without `android/key.properties`, release assemble/bundle **fails on purpose**
(no debug-key fallback).

**Direct-install APK** (our own website / Viber, not a store — the only
distribution channel with no billing rule, so the only build that keeps the
purchase UI):
```bash
flutter build apk --release --dart-define-from-file=env.local.json --dart-define=COMMERCE_UI=true
```

## Notes
- The auto-mode safety classifier may still block prod writes even with the
  permission allow-rules; if so, hand the exact command to the user.
- Reflect the deploy in `PROJECT_SPEC.md` §12 + the `supabase-backend` memory.
