# App Review notes (paste into Connect → App Review Information)

## Demo access
All In One POS is a B2B offline POS for small retailers. Reviewers can:

1. Install the build and complete onboarding (choose Myanmar or English).
2. Use **Free plan** immediately to sell — no account, no key, no purchase.
3. For Premium features (Analytics, Staff accounts, Sync, web storefront),
   paste the review licence key below into **Settings → License → Activate**.

⚠️ **A working Premium key is mandatory for every submission.** The app sells
nothing in-app (see *Business model* below), so a reviewer with no key can
only see the Free tier and cannot exercise the Premium features the listing
describes — that fails guideline 2.1 on its own, independently of anything
else in these notes. Mint a fresh review key in the admin console (Requests →
Generate license key, 3 months) and paste it here before submitting.

**Sign-in required:** No (Free plan works offline; the review key needs no
account either).  
**Demo account:** _(only if submitting an Online-tier review path)_  
**Premium review key:** _(fill before submit — `MMPOS1.…`)_  

## Hardware
- Bluetooth thermal printer is **optional**. The app works without a printer; printing can be skipped.
- Camera is used for barcode / license QR scan; Simulator may skip.

## Business model / IAP — guideline 3.1.3(b), Multiplatform Services

All In One POS is a business (B2B) point-of-sale service for small retailers,
available on **Android** and on the **web** (admin console, shop storefront,
invoice viewer). Subscriptions are sold only to businesses, outside the app.

This binary contains **no commerce of any kind**: no IAP products, no prices,
no "Buy"/"Upgrade"/"Pay" call to action, no link or phone number pointing at a
way to pay, and no collection of payment details or payment proofs. A business
that already holds a licence redeems it here — by typing its licence key, or by
signing in to the shop account it already has — which is exactly the access to
previously-purchased content that 3.1.3(b) provides for. The app unlocks tools
for operating a **physical retail shop**.

This is enforced at build time, not by convention: `lib/core/build_flags.dart`
defines `kCommerceUiEnabled`, which **defaults to false**, and the App Store
build never passes the `COMMERCE_UI` define. `test/commerce_ui_gate_test.dart`
fails the build if that default is flipped or if any purchase/pricing string
reappears in a file that does not consult the flag. See PROJECT_SPEC §12 entry
245 for the full list of what the flag removes.

A free 2-month trial is available in-app. It costs nothing, requires no
payment method, and is limited to one per device.

## Account deletion
Signed-in shop **owners** can delete their online account in Settings → Shop Login → Delete account (password confirm). This removes Auth users for owned shops and associated cloud shop data; the device returns to Free plan.

## Locale
Default UI language is Myanmar; toggle to English in Settings.

## Contact
Use the App Store Connect team contact email; Support also via in-app Viber.
