# App Review preparation — account Premium

Updated 2026-10-04. This is preparation evidence, not a claim of approval.
Do not submit until the readiness gates below are complete.

## Business model and policy assessment

All In One POS is a free offline retail POS with account-based optional
Premium tools and a web service. Free selling requires no purchase or account.
The App Store/Google Play binaries use COMMERCE_UI=false: no Premium pricing,
buy/pay buttons, payment proofs, external checkout links or contact-to-buy
cards. An existing Premium owner signs into the shop account and checks its
status. Customer license keys/QR activation are retired.

Apple §3.1.3(b) is **not** an exemption from IAP: it explicitly requires the
same items to be available as IAP. Assess whether the actual product meets
§3.1.3(f), a free companion to a paid web-based tool, with no purchase or
external purchase CTA inside the app. Do not describe individual shop-owner
sales as enterprise-only sales under §3.1.3(c). If the product does not qualify
for an applicable exception, implement Apple IAP before offering its paid
functionality on the App Store. No approval is guaranteed by this document.

Google Play permits consumption-only apps: users may sign in to access a
service acquired elsewhere, with no in-app alternative payment steering.
If selling Premium inside a Play-distributed app, use Play Billing unless an
applicable exception/program explicitly permits the chosen flow.

The directly installed owner development build uses COMMERCE_UI=true to
exercise external purchase UI. **Never upload that binary to either store.**
Do not place COMMERCE_UI in the shared env.local.json.

## Reviewer access

Before submission, provide a dedicated, working owner account with Premium
active for a review-only shop. Use the store's private review-information
fields for login credentials; do not put credentials in this repository.
Never add a hidden review bypass. Reviewers and customers use the same code.

Reviewer instructions after backend rollout:

1. Open the app; choose English or Myanmar and complete onboarding.
2. Free POS features are immediately available without an account.
3. For Premium, open Settings → shop account and sign in with the supplied
   reviewer credentials. Check the account's Premium status in Settings.
4. Exercise Sell, Inventory, Orders/Invoices, Analytics and Settings. Supply
   an owner PIN and staff instructions in private reviewer notes if needed.
5. Bluetooth printing is optional; no external hardware is required to review.

## Submission readiness gates

- Confirm applicability of Apple's no-IAP exception to the actual web/app
  service and describe it accurately. Otherwise complete StoreKit billing.
- Rehearse and deploy account Premium backend; current phone-only delivery
  does not establish server readiness.
- Provision and manually verify the dedicated Premium reviewer account,
  owner PIN, staff entry/exit and successful daily opening.
- Build a fresh store binary with COMMERCE_UI=false, and inspect Free,
  active Premium, grace/expired, offline and sign-in states in both languages.
- Inspect support contact destinations for purchasing prompts; support must
  remain support, with no app-linked Premium checkout funnel.
- Verify account deletion in-app and the public deletion link required by
  Google Play; complete privacy/data-safety declarations against actual SDKs.
- Remove stale key/trial/per-device claims from listing and submission text.
- Verify store screenshots and metadata match this exact submitted binary.

## Evidence and limitations

Rendered store-screen regression checks cover signed-in Free, active, grace and expired accounts in English and
Myanmar, including hiding checkout, contact-to-buy, vendor phone and trial
purchase CTA. The default commerce flag, neutral gate CTA and localization
parity are checked separately. This is not the full physical submission
matrix or a review decision. Local Premium code is not yet live server code.

## Official sources

- https://developer.apple.com/app-store/review/guidelines/#other-purchase-methods
- https://support.google.com/googleplay/android-developer/answer/10281818
- https://support.google.com/googleplay/android-developer/answer/9858738
