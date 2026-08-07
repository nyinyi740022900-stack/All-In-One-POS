# TestFlight smoke checklist

Use after a build appears under **App Store Connect → TestFlight** (Internal first, then External).

## Install
- [ ] Internal tester (team) installs via TestFlight
- [ ] App icon label shows **GoldPOSMM**
- [ ] Version / build matches uploaded IPA (`1.0.0 (N)`)

## Core POS
- [ ] Onboarding completes (EN + MY toggle)
- [ ] Free plan: create product, sell, see invoice
- [ ] Cloud sync when online (status returns to idle)
- [ ] Bluetooth printer pair + one receipt **or** documented skip if no hardware

## License / support
- [ ] License screen shows Support / Viber path (no broken self-serve trial)
- [ ] Online sign-in (if used) claims device and loads shop data

## Storefront
- [ ] Owner publishes / opens storefront settings
- [ ] Place a guest order on https://goldposmm-shop.vercel.app/{slug}
- [ ] Order appears in Orders after sync; local notification may fire

## Multi-shop A→B→A (#74)
Requires two shops on one Apple ID / device:

1. Activate or switch to **Shop A**, create a unique product name, sync.
2. Switch to **Shop B** (Branches or account claim) — confirm A’s product is gone, B’s data loads.
3. Switch back to **Shop A** — confirm A’s product still present (per-shop DB; no wipe of the other file).
4. Note pass/fail + device OS in support log.

## External TestFlight
- [ ] Add 2–3 Myanmar shop owners as external testers (or public link)
- [ ] Beta review approved (first external build)
- [ ] Collect crash-free session from Sentry (if DSN in build)

## Sign-off
Date: ________  Build: ________  Tester: ________  Result: Pass / Fail
