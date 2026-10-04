# Account-based Premium design

Date: 2026-10-03 (Asia/Singapore)
Status: product direction approved in chat; detailed migration/lapse policy below is for written review. No implementation or deployment is claimed.

## 1. Approved product decisions

- Premium purchase requires a real owner account. No customer-facing activation keys, key QR provisioning, or offline licence codes.
- Free remains usable without an account or internet.
- Two plans: Free and Premium. Remove Online/Offline pricing tiers.
- Myanmar Premium price: 20,000 MMK per calendar month or 200,000 MMK per year, per shop. No transaction fee. Annual saving: 40,000 MMK against twelve monthly payments.
- Each shop has its own subscription and allowance of three concurrent POS devices, including owner and staff devices. One owner account may manage several shops; payment for one does not unlock the others.
- Two-calendar-month trial, deliberately started by the owner rather than automatically on signup. The first eligible shop receives it once per owner account; creating further branches does not reset eligibility.
- Premium remains available for fourteen days after subscription expiry. Renewal within grace extends from the old expiry; renewal after grace extends from the renewal time.
- Retain the existing signed-entitlement approach and offline-first sales ledger.

## 2. Feature contract

| Capability | Free | Premium / trial / grace |
| --- | --- | --- |
| Sell, payments, credit sales, refunds, invoice history, receipt printing/sharing | Full | Full |
| Products, stock tracking, barcode, low-stock alerts | Full | Full |
| Customers, credit collection, expenses, cash register, supplier directory | Full | Full |
| Number of products and sales | Unlimited | Unlimited |
| Basic daily/monthly Sales, Collected and Owed summaries | Yes | Yes |
| Detailed profit, trends, comparison, P&L, cash flow, balance sheet, tax reports, equity tools | No | Yes |
| Purchase orders and supplier payable management | No | Yes |
| Separate staff accounts, permissions management, staff performance reporting | No | Yes |
| POS cloud sync across devices | No | Yes, three active devices per shop |
| Public storefront and online order intake | No | Yes |
| Local backup/restore and raw business-data export | Yes | Yes |

Basic analytics must not expose detailed profit through a deep link, hidden tab, PDF export, or a retained Premium screen. Raw data export remains available; exporting advanced calculated reports requires Premium.

Local owner PIN / staff mode remains a Free safety tool; it is distinct from separately authenticated staff accounts. Premium never changes an existing user's authorization into owner authorization.

## 3. Account and shop lifecycle

Free onboarding stays account-optional. Upgrade and Try Premium both lead to account creation/sign-in, then explicit shop selection, then trial or purchase. Signup itself creates a Free cloud identity, not an automatic trial.

When registering the existing local Free shop, promote its identity using `ShopDataTransitionService` and the pending-promotion recovery marker. Move its existing products, sales, settings and queued writes into that shop; do not create an empty shop and strand the data. Joining a different existing account's shop must use the existing guarded shop-switch flow, not merge unrelated local ledgers.

A shop registered as Free has an online identity for licensing but no POS data sync entitlement. The billing/account connection is allowed even when business-data sync is unavailable.

The owner can create/manage other shop identities without granting them Premium. A branch-selection list must remain reachable for selecting a shop to renew even when the current shop is Free. Advanced multi-shop reporting is Premium; access to one's account and billing is never gated by Premium.

Passwords and sessions use Supabase Auth and existing secure storage. Do not put credentials in Drift, backups, licence payloads or diagnostics. Existing email verification/recovery flows must stay usable.

## 4. Subscription and device authority

Do not retain one licence key row as both subscription and device authority. Introduce cloud-only records:

- `shop_subscriptions`: one row per shop, authoritative plan, expiry, archived/revoked state and monotonically increasing revision. Reads are shop-scoped; writes occur only through authorized backend operations.
- `shop_devices`: unique `(shop_id, device_id)`, release state, registered account/session information and activity timestamps. A database transaction serializes slot allocation for each shop so simultaneous fourth-device claims cannot succeed.
- `account_trial_claims`: unique owner account claim, with shop, trial start and end. The trial claim and subscription update commit atomically. Owner-only reads; no direct client writes. Branch creation, concurrent requests, retries and device reinstall cannot issue a second claim.

These tables are server bookkeeping, not business-data tables to sync through Drift. Each table must enable RLS with shop-isolation or owner-account policies as appropriate; service-role-only mutations are enforced through SQL privileges and authenticated Edge Functions. A self-editable `org_branches` link alone must never prove entitlement to another shop: restrict membership creation to backend operations with proven ownership and audit existing links before migration.

Separate staff users may claim devices only through valid shop membership. Only an owner may start a trial, purchase, manage devices or change membership. Returning `shop_id` from a client body does not prove ownership.

The owner can replace a lost phone by explicitly releasing its slot and registering the new device. After three devices, show the device list and release action; do not offer the old extra-device fee or key-generation flow in this version. Release is about a slot, not deleting shop data.

Free needs one designated local POS device per shop; it is not a cloud-recovery plan. Changing a Free device requires an owner-directed local backup/restore or reactivating Premium to restore cloud data. Account sign-in alone must not claim that unsynced Free data has been restored.

## 5. Signed receipts and time

Retain Ed25519 verification with the private signing key only in Supabase secrets. Use a versioned receipt that binds shop, authenticated user and device, and carries plan, subscription expiry, issued-at time and revision. Free needs no receipt. The public key is safe to ship.

Receipt verification must check identity and supported version/plan before unlocking Premium. Check shop/user/device binding before using issued-at to reset trusted time. Never trust editable cache expiry, tier or realtime flags to grant capabilities.

Distinguish `verificationRequired` from `expired`: a missing or invalid receipt is not evidence that a paying shop's subscription ended. Keep sales available and show an online-recheck recovery action. Do not overwrite the subscription identity with a `FREE` key placeholder on lapse.

Recompute the cached licence's expiry locally on startup, app resume and a local timer even when online refresh fails. Reuse the monotonic trusted-time guard. Online refresh fetches the selected shop subscription by authenticated ownership/membership, without a key. Refresh responses must not apply after a newer shop/account transition.

A positive backend rejection (archived shop, released device or revoked membership) removes local Premium entitlement immediately; a network timeout does not. Keep the highest accepted subscription revision and reject older receipts for that shop/device.

Offline devices cannot learn about a new revocation until reconnecting. Binding a receipt and tracking revision do not solve arbitrary rooted-device storage rollback. Do not describe offline revocation as instantaneous or this protection as impossible to bypass.

## 6. Lapse, sign-out and recovery policy

This section makes the approved feature matrix operational and needs written review.

- During fourteen-day grace all Premium capabilities stay available, with a renewal notice.
- After grace, Sell, refunds, local inventory, credit collection, expenses, invoice access, basic summaries, backup/restore and raw export continue. Local business records are never deleted on lapse.
- Freeze new staff invitations and permission changes, but retain existing authenticated staff roles for local core POS work on devices already provisioned to that shop. Staff do not acquire owner rights when their account is signed out or Premium lapses.
- Stop cross-device POS sync and realtime after grace. Retain the outbox unchanged, visibly mark cloud sync paused, and resume draining it only after verified renewal. Shop-switch and backup-restore safety checks continue to protect pending writes.
- Stop accepting new storefront orders server-side after grace. Customers see a temporary-unavailable message. Existing accepted orders remain accessible locally for fulfilment, cancellation and customer obligations.
- Preserve access to existing supplier payable balances and recording repayment of existing debt. New purchase orders and advanced payable management require Premium. This recovery exception avoids trapping an obligation created during trial.
- Signing out immediately removes account Premium on that device and releases its slot best-effort. Retain its local shop data, core POS access and role restrictions. A released/sign-out device must not resume sync until signed in and provisioned again.
- Renewal refetches the same shop identity and restores Premium without re-entering a key, reminting a shop or rewriting old sales.

## 7. Purchase and renewal

Use one account/shop-based billing path. Myanmar manual approval and existing international checkout may remain payment adapters, but neither accepts a device reference/key as ownership proof.

Each purchase request has a client-generated idempotency id and server-selected shop/plan/amount. Fulfilment and webhook processing apply one payment once using unique processor/request identifiers and a database transaction. Retries must return the previously fulfilled result rather than extend again.

Update admin approval, renewal SQL, request receipts, Lemon Squeezy checkout/webhook and the public `/renew` page together. Owner-selected shop comes from authorized account membership. Remove anonymous device-id purchase and new key issuance. Keep MMK integers separate from POS currency and international billing amounts. The approved 20,000/200,000 prices apply to Myanmar; do not silently change configured international currency/variant pricing.

Do not remove the existing store-build commerce visibility flag as part of this redesign. Account sign-in, neutral licence status and recovery remain reachable in every build.

## 8. Existing installation migration

Inventory the deployed database read-only before deciding cutover: licence rows, shop/account links, bound device counts, active trial/paid expiries, allowances, archived rows and outstanding payments. The changelog records live signing by `activate` v33; older “not deployed” notes are not evidence of today's deployment state.

For each unambiguous shop, backfill one subscription and separate device records. Preserve paid expiry, shop id, archived state, local database filenames and sale UUIDs. Multiple device licence rows become one subscription, not multiple charges. Preserve a valid existing paid/trial expiry using the maximum non-deleted expiry; fail review for inconsistent account ownership instead of choosing an arbitrary owner.

Historical trial records for identified owner accounts create consumed trial claims; migration never restarts trial. Anonymous legacy shops cannot claim ownership merely by knowing the public device id. A current, authenticated legacy shop session plus owner verification or a manual support ownership process is required to attach an account.

Retain legacy records only as migration/audit evidence. New application, admin, billing and invoice-web flows never issue or accept activation keys. Once conversion is verified, retire legacy key endpoints; a trusted session recovery path may migrate an existing shop without taking a key input. Stage backend compatibility before switching the app, then close legacy entry points so old clients cannot bypass the new policy.

If deployed records contain paid extra-device allowances, do not silently discard something purchased: list them in the migration report and resolve those shops before cutover. No blanket three-device truncation or deletion.

Invoices Web currently activates with a key and must move to account authentication. A provisioned browser accessing synchronized shop data counts as a device; a public customer invoice link does not. Raw local invoice access/export in the app remains Free.

## 9. Implementation boundaries and order

1. **Backend authority and migration:** additive cloud schema, restricted ownership links, atomic trial/device/renewal operations, authenticated receipt response and staging migration fixtures.
2. **Account client lifecycle:** Free signup, explicit trial, safe local-shop promotion, receipt/expiry/revocation handling and owner device management. Remove key UI, key QR and pricing-tier UI.
3. **Capability integration:** Free summaries, advanced analytics gates, sync pause/recovery, staff lapse behavior, storefront server gate, existing-obligation access and raw export.
4. **Billing and companions:** account `/renew`, admin fulfilment, gateway idempotency, invoice-web authentication and removal of legacy inputs.
5. **Cutover:** staging migration rehearsal, full verification, backend deploy, companion/admin deploys, device installation and real owner/staff smoke checks. Disable legacy endpoints only after verified migration readiness.

Expected modules: `lib/features/license/`, `lib/features/account/`, `lib/features/analytics/`, `lib/features/staff/`, `lib/features/support/vendor_config.dart`, `lib/features/settings/`, `lib/features/suppliers/`, `lib/data/sync/`, `lib/invoices_web/`, `lib/storefront/renew_request_page.dart`, `lib/admin/`, `supabase/functions/activate/`, `supabase/functions/admin/`, storefront submission functions, gateway functions and new migrations after 0093.

Keep current unrelated UI edits intact. All user-facing copy needs English/Myanmar parity and generated localizations. Update `PROJECT_SPEC.md` sections 6 and 12 and the stale licensing guidance in `AGENTS.md`/`CLAUDE.md` alongside implementation, explicitly describing deployed behavior versus planned behavior.

## 10. Acceptance checks

- Free fresh install works offline without account; core sales and raw export work without product/sales caps.
- Free daily/monthly Sales/Collected/Owed work; profit/report routes and exports remain Premium-gated.
- Registering a local Free shop preserves products, sale UUIDs, shop settings and pending outbox writes, including restart during promotion.
- Signup remains Free until explicit trial start; owner account A cannot start a second trial via branch, phone change or concurrent request. Account B's first eligible trial is independent.
- Three concurrent owner/staff device claims succeed; a fourth is refused. Concurrent claims at the boundary do not over-allocate. Releasing one allows a replacement.
- Shop A's subscription, device release, settings, receipt and trial never unlock or alter shop B.
- Cached expiry edits, unsupported receipts, wrong shop/user/device signatures and older revisions do not unlock Premium.
- Running offline across expiry plus fourteen days changes to Free without restart; selling continues and sync pauses without clearing its queue.
- A timeout retains a valid cached receipt; a confirmed archive/release/revocation removes Premium. Verification-required UI does not say expired.
- Staff can complete core local sales after lapse without owner elevation; existing orders and debts remain actionable; new storefront orders are rejected server-side.
- Renewal inside grace extends from old expiry; past grace from now; monthly/yearly and month-end dates agree between backend and client.
- Repeated request approval/webhook/retry grants paid time once and restores Premium to the same shop with no key.
- Sign-out removes Premium without losing local records; re-sign-in and valid slot registration restores it.
- Legacy migration preserves legitimate expiry/devices and rejects ambiguous ownership, reused trials and archived rows; extra paid allowances are reviewed before cutover.
- Mobile, admin, `/renew`, provisioning and Invoices Web have no customer-facing key path or Online/Offline price choice.
- Run targeted unit/widget/backend tests, `flutter analyze`, full `flutter test`, relevant `deno check`, provider invalidation/key-scope/i18n guards and the repository ripple-effect audit. Test migrations on staging before production. Install and smoke-test the release app on the paired device.

## 11. Review boundary

The chat approval covers the plan, price and feature split in sections 1–2. Sections 3–8 add concrete policies needed for implementation, especially Free device replacement, existing staff/debt access after lapse, authenticated legacy conversion and one trial per owner. Review those before writing the implementation plans. This document is a design artifact, not a claim that the existing app already behaves this way.
