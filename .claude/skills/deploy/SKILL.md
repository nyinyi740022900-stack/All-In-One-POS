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
```
Secrets (rarely): `supabase secrets set NAME=value --project-ref ...`.

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

## 3d. Desktop (macOS/Windows) — Phase 2, slice 1, in progress
The *real* POS (Sell/Inventory/Orders, not just Invoices) as a native desktop
app — `macos/`/`windows/` platform folders scaffolded via
`flutter create --platforms=macos,windows .`, same `lib/main.dart` entry point
as mobile, no Drift/wasm needed (native `NativeDatabase` already works on
desktop). Run/build:
```bash
flutter run -d macos --release --dart-define-from-file=env.local.json
```
⚠️ In **debug** mode you may see a `RenderBox was not laid out` /
`mouse_tracker.dart` assertion loop right at launch — this is a known
debug-only Flutter-desktop artifact (stripped in `--release`), not a real bug;
verify with `--release` before concluding something is broken.

Windows: `flutter build windows` **refuses to run on a non-Windows host** —
there is no way to build, let alone test, the Windows target from a Mac. It
needs an actual Windows machine or a CI runner (e.g. GitHub Actions
`windows-latest`) — not yet set up.

No GUI-automation/screenshot tool exists for native desktop windows in this
harness — verification here is necessarily code-level (`flutter analyze` +
`flutter test` + process-stability from logs), not visual/interactive. Actual
onboarding → license activation → feature walkthrough needs a human at a
real, display-attached machine.

## 4. App → iPhone (wireless)
```bash
flutter run --release -d 00008150-001A44C41E08401C --dart-define-from-file=env.local.json
```
Run in the background; wait for "Flutter run key commands", then kill the
process (app stays installed). If it fails with "Could not run … on iPhone",
the phone is locked/asleep OR a native plugin failed to compile — check the log
for `Swift Compiler Error` before assuming it's the device.

## Notes
- The auto-mode safety classifier may still block prod writes even with the
  permission allow-rules; if so, hand the exact command to the user.
- Reflect the deploy in `PROJECT_SPEC.md` §12 + the `supabase-backend` memory.
