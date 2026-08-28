# Multi-country foundation (languages + currencies later)

**Date:** 2026-08-28  
**Status:** design approved in chat; not implemented  
**Product:** All In One POS

## 1. Why

The product stays Myanmar-first today. The owner is applying for a **SaaS license** payment gateway so shops in other developing countries can pay for Premium. When that is approved, the app must take extra **UI languages** and extra **POS currencies** without rewriting sales, stock, or ledger math.

Today the code treats Myanmar as the universe:

- `Money` is integer **kyat** with no minor unit (`lib/core/money.dart`, PROJECT_SPEC §4.3).
- On-screen currency suffix follows **UI language** (`Ks` vs `ကျပ်`), not the shop.
- Checkout tender chips are hard-coded Myanmar notes (`500 / 1_000 / 5_000 / 10_000 / 20_000`).
- Storefront phone normalize / blocklist assume `09` / `+959`.
- Default wallets are KBZPay / Wave.
- Premium list price is `app_config` `price.monthly` = `20000` (MMK).

Those assumptions must become data on the **shop** (country + currency) and a **country pack**, not Dart constants.

## 2. Goals (this foundation)

1. Keep live behaviour identical for existing Myanmar shops: MMK, no decimals, EN+MY UI, 20,000 MMK/month Premium.
2. Stop encoding “this product is Myanmar-only” in money math, receipts, tender chips, and phone rules.
3. Split **POS money** (what the shop sells in) from **billing money** (what the shop pays us for Premium).
4. Make adding a country later a **pack + ARB + billing row**, not a ledger rewrite.

## 3. Non-goals (explicit)

- No second live country, language, or currency in this implementation.
- No FX, no dual-currency books, no mixed-currency cart.
- No changing a shop’s POS currency after its first finalized sale.
- No card/QR checkout for the shop’s *customers* (POS/storefront). Gateway work is **Premium license payment only**.
- No Apple/Google In-App Purchase. Store builds still compile with `kCommerceUiEnabled = false` (guideline 3.1.1). Payment stays on `/renew` web.
- No renaming the public brand or dropping Myanmar as the default country.

## 4. Two money streams

| Stream | Owner | Unit | Where it lives |
|---|---|---|---|
| POS | the shop | one ISO 4217 code per shop | every sale / stock / till / AP / AR integer column |
| Billing | All In One POS | ISO 4217 per **shop country**, may differ from POS | license price list + `/renew` + gateway |

Example later: a Thai shop sells in THB (POS) and pays Premium in USD or THB (billing). Those integers never add together.

Admin “credit N months” uses **billing** amounts, not POS totals.

## 5. POS money model

Keep integer arithmetic. Do **not** introduce `double` / `Decimal` for money.

- `Money` wraps `int amount` = **minor units of the shop’s POS currency**.
- Rename the field off `.kyat`. Callers that still say “kyat” in comments are Myanmar-era leftovers and should die in the same change-set.
- `CurrencyDef` (code, not on every `Money` instance — a shop has one POS currency):
  - `code`: ISO 4217 (`MMK`)
  - `exponent`: decimal places (`MMK` = `0`, later `THB`/`USD` = `2`, `VND` = `0`)
  - `asciiSymbol`: thermal / CSV alignment (`Ks`)
- Display:
  - Numeric grouping + fraction digits from `exponent` (MMK `1250` → `1,250`; a future exponent-2 currency `1250` → `12.50`).
  - On-screen suffix is **localized label of that currency** (EN `Ks` / MY `ကျပ်` for MMK), not a second currency. UI language must not pick MMK vs THB.
  - Thermal receipts keep the ASCII symbol so columns stay aligned (existing printer rule).
- SQLite / Postgres money columns stay `INTEGER`. Existing MMK rows do not migrate numerically (exponent 0, same ints).
- Unit tests must cover exponent `0` and exponent `2` formatting even though only MMK is live — so THB cannot land as a surprise rewrite.

`cashTenderSuggestions` takes the country pack’s note list, not `kyatNotes`. MM pack keeps `[500, 1000, 5000, 10000, 20000]`.

## 6. Shop country + currency

One shop = one country + one POS currency.

- Default for every existing and new shop: `country_code = MM`, `currency_code = MMK`.
- Stored **per shop**, not per device. A device that `switchBranch`es must not keep the previous shop’s currency (same class of bug as device-global settings keys).
- Authoritative local copy follows today’s shop-profile pattern: `SettingsRepository` KV keyed by `shopId`, written through to synced `shop_profiles` so other devices and admin see it.
- Columns on Drift `ShopProfiles` and Postgres `shop_profiles`: `country_code text not null default 'MM'`, `currency_code text not null default 'MMK'`.
- UI: read-only on Shop Profile after the shop has any finalized `sales` row; editable only before that (onboarding / empty shop). Repository rejects a currency change when sales exist.
- Unknown / empty code at read time fail-closed to `MM` / `MMK` (never blank, never throw in the sell path).

Ripple: backup/restore, `wipeSyncedData` / `promoteShopIdentity`, sync mapper, `007N` RLS already on `shop_profiles` (add columns only; do not drop `shop_isolation`).

## 7. Country pack vs UI language

**UI language** stays a device preference (today `en` + `my`). Adding Thai later is a new ARB pair + `flutter gen-l10n` + `i18n_parity_test`. It does not change money.

**Country pack** is keyed by `country_code` and owns:

- POS `CurrencyDef`
- Cash note denominations (minor units)
- Phone normalize + example (`MM`: keep current `09` / `9` / `+959` / spaces-dashes rules)
- Default payment-account names / method ids for that country (MM: cash, kbzpay, wavepay, ayapay, …)
- Default billing country (usually the same code)

Only the `MM` pack ships in this foundation. A later country is a new pack entry, not a fork of `Money`.

A shop may run **English UI + Thai POS currency** when that pack exists. Language and currency are independent.

## 8. Premium billing + gateway

Myanmar list price does **not** change: monthly `20000` MMK, yearly `200000` MMK (`0071_premium_price_20000.sql` / `app_config`).

Introduce a billing catalog in code (const map is enough until a second country exists):

```
{country: MM, plan: monthly, amountMinor: 20000, currency: MMK}
{country: MM, plan: yearly,  amountMinor: 200000, currency: MMK}
```

`/renew` and admin credit read this catalog by the shop’s **country**, never from POS sale totals.

**Gateway port** (no vendor name in call sites):

```
abstract class LicensePaymentGateway {
  Future<LicenseCheckout> createCheckout({
    required String shopId,
    required String plan, // monthly | yearly
    required String billingCountry,
  });
}
```

Today’s MyanMyanPay / manual Viber / admin-confirm path is the MM adapter. Stripe/Paddle/etc. plug in behind the same port after approval. Do not put a vendor SDK into `license_screen.dart` or `Money`.

Store builds: `COMMERCE_UI` stays default `false`. Direct-install / web `/renew` remain the purchase surfaces.

License request rows that already store a single integer amount stay valid for MMK (exponent 0). When a non-zero-exponent billing currency appears, store `amount` + `currency_code` on the request (add the column then, not now, unless the table already has a place for it). Until a second billing currency exists, do not migrate historical `license_requests`.

## 9. What “add a country later” looks like

After the gateway is approved, a new country is:

1. `CountryPack` + `CurrencyDef` (notes, phone, wallets, exponent).
2. Billing catalog rows (Premium price + billing currency for that country).
3. Gateway adapter implementation for that country (or the same adapter if the processor covers it).
4. Optional: ARB language files if we ship a new UI language. English-only UI + local currency is allowed.
5. App Store / Play listing for that country. In-app Pay online still gated by `kCommerceUiEnabled`.

No change to how a sale is inserted. No rewrite of `Payments` / `CashSessions` / FIFO lots.

## 10. Testing

- `Money` format: exponent 0 and 2; thousands separators; thermal ASCII symbol separate from localized suffix.
- Two shops: MMK pack on A does not leak into B (`settings_repository_test` two-shop pattern).
- Currency change rejected after first sale; allowed on empty shop.
- `cashTenderSuggestions` uses pack notes (MM list unchanged).
- Phone normalize still matches current MM fixtures (`test/storefront_phone_test.dart`).
- Billing catalog MM prices still 20000 / 200000; a test fixture for a second country must not be summable into a POS total.
- `flutter analyze` clean; i18n parity if any ARB keys are added (`currency` labels stay EN+MY).

## 11. Implementation notes (for the later plan)

- Drift `schemaVersion` currently **37** — next bump is 38 with `_safeAddColumn` for the two shop_profiles fields.
- Follow CLAUDE.md synced-column checklist: tables, database, `build_runner`, mapper, Supabase migration with RLS left intact, ripple grep.
- `PROJECT_SPEC.md` §4.3 updates when this ships (integer **minor units**, shop currency; MMK exponent 0 is the live case), plus §12 changelog.
- Do not put `COMMERCE_UI` in `env.local.json`.

## 12. Decisions locked in chat

- Path: shop locale pack (not display-only i18n, not full FX ledger).
- Now: foundation only. Languages and extra currencies after gateway approval.
- Gateway: SaaS Premium only, not shop-customer checkout.
- POS currency and billing currency are independent.
- Money storage: integer minor units; MMK numbers on disk do not change.
- Currency locked after first sale.
- UI language is a device setting; POS currency is a shop setting.
