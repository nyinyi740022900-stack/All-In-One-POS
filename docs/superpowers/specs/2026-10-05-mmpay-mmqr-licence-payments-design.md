# Myan Myan Pay (MMQR) licence payments — design

Date: 2026-10-05 (Asia/Singapore)
Status: **server side implemented and tested, nothing deployed.** Migration
0098, `_shared/mmpay.ts`, `_shared/mmpay_mode.ts`, the `mmpay-webhook` function
and three `storefront` actions exist and pass CI; the `/renew` page (§7) is not
built, nothing is deployed, no sandbox key has been issued and no KYC submitted.
See §16. **Updated 2026-10-05 after reading the
published API reference and the `mmpay-node-sdk@1.1.4` source: Q1 and Q3 are
answered, Q2 is designed around, Q4 and a newly found blocker (Q7) still need
the merchant console.** See §11.

## 1. Why now, and what changed

The 2026-08-25 evaluation rejected MMPay on one operational ground: the merchant
console had no Developers/API/Webhooks section at all, so API access was not
self-serve and had to be negotiated with support. That blocker is gone. A
self-serve developer console now exists at `developers.myanmyanpay.com`
(version 1.2.9) with Applications, Sandbox, Transactions, Disbursements and API
Documentation. `docs.myanmyanpay.com` documents `pay()` / `sandbox_pay()` MMQR
creation, webhook events (created, success, failure, refund, cancel, expire,
with explicit duplicate-delivery heartbeats) and SDKs for Node/TS, Python, PHP,
Java and the browser.

What has *not* changed, and is not re-litigated here:

- **Storefront payments stay out of scope.** No sub-merchant, split-payment or
  third-party payout is documented. Collecting on a shop's behalf makes the app
  owner a money transmitter; MMPay's own CBM/AML terms prohibit remittance,
  penalty "account banned, funds frozen". Per-shop KPay/Wave number plus
  transfer proof remains the storefront model.
- **In-app purchase stays out of scope.** `kCommerceUiEnabled` is false in every
  App Store / Play build. MMQR is a web `/renew` surface only.

So the scope of this document is exactly one thing: **an owner renewing their
own shop's Premium subscription on `shop.allinonepos.app/renew`, in MMK, from a
Myanmar mobile banking app, without an admin approving a screenshot by hand.**

## 2. What this replaces

`/renew` currently offers three ways to pay, and only one of them is automatic:

| Path | Today | Cost per 20,000 MMK renewal |
| --- | --- | --- |
| International card (Lemon Squeezy) | Automatic, signed webhook grants the term | ~2,000–2,500 MMK, and most Myanmar shops have no usable card |
| KBZPay / WavePay manual transfer | Owner uploads proof, admin clicks Confirm in the console | 0, but a human and an unbounded wait |
| — | — | — |

MMQR is the missing row: automatic *and* local. 120,000 MMK one-time activation
plus 100 MMK per transaction, 0% MDR, settlement to the merchant's own KBZ or
AYA account in about two business days. Against the card path it saves roughly
2,400 MMK per renewal, so the activation fee is recovered after about fifty
transactions — but the actual justification is not the fee. It is deleting the
screenshot-and-approve loop, which is the only part of the renewal flow that
cannot be made to finish at 2am.

The manual path is **kept**, not removed. It is the fallback when MMPay is down,
when the owner's bank is not in MMPay's coverage, and during the period before
KYC is approved.

## 3. The decision that shapes everything else

MMQR is a **one-off payment**. Lemon Squeezy is a **recurring subscription**.
The existing `billing_checkouts` machinery is subscription-shaped:
`subscription_id` is unique and non-null at fulfilment, `fulfill_gateway_payment`
refuses a payment without one, and `reserve_gateway_checkout` requires a numeric
processor variant id.

Two options were considered.

**Option A — a separate `mmpay_orders` table.** Clean, no change to any existing
RPC. Rejected: it loses the one-open-checkout-per-shop guard that 0097 was
written to provide. A shop could hold an open Lemon Squeezy subscription
checkout and an open MMQR at the same time and pay both — which for a recurring
processor is not merely "two months bought", it is a live subscription the owner
did not know they still had, plus a manual payment, plus a refund conversation.

**Option B (chosen) — one checkout table, two providers.** `billing_checkouts`
gains a `provider` column; the open-checkout lock, the ownership check and the
`shop_subscriptions` row lock stay shared across both providers, so the guard
holds *between* providers and not merely within each one. Fulfilment splits:
Lemon Squeezy keeps `fulfill_gateway_payment` untouched, MMQR gets its own
`fulfill_mmpay_payment` that never writes `subscription_id`.

A shop that already has a live Lemon Squeezy subscription is refused an MMQR and
sent to the customer portal, reusing the existing `subscription_already_exists`
409 and its `management_url`. Selling a one-off month to someone who is already
being billed monthly is a support ticket, not a sale.

## 4. Trust model

Two rules, both inherited from how the Lemon Squeezy integration already
behaves, and both non-negotiable:

1. **The server owns the amount and the term.** The client sends `shop_id` and
   `plan` and nothing else. The price is 20,000 MMK for one month and 200,000
   MMK for twelve, hard-coded in the RPC — the same two literals
   `fulfill_account_payment` already checks, so there is exactly one place in
   the system where a Premium price lives in SQL and it stays that way.
2. **The webhook is a hint, never an authority.** On every callback the function
   re-queries MMPay's own transaction-status endpoint for that order id and
   grants time only on what the API says, exactly as `lemonsqueezy-webhook`
   re-fetches the subscription rather than trusting the invoice payload. This is
   the design whether or not MMPay signs its callbacks (see §11 Q1) — if a
   signature exists it is verified *in addition*, with the same timing-safe hex
   comparison `verifySignature` already uses, and a missing or bad signature is
   a 401 before any API call is made.

Beyond re-query, the fulfilment path asserts: the returned status is the
terminal paid state; `amount` equals the expected amount for the stored
`months`; `currency` is MMK; the order id is the one bound to this checkout row;
and the merchant id is ours. An amount mismatch is a hard failure and a logged
event, never a partial grant.

**Test mode.** A new `_shared/mmpay_mode.ts` mirrors `gateway_mode.ts` exactly:
`mmpayTestMode()` returns true only on a non-production Supabase project that
explicitly set `MMPAY_TEST_MODE=true`, and **throws** if the production host
(`gnikispsurwrmkspuisj.supabase.co`) has the flag set, so sandbox money can
never buy a real month. `mmpayAvailable()` reports whether the secrets are
present and the mode is legal, feeding the same `card_payment`-style capability
flag the page already understands.

## 5. Schema — migration `0098_mmpay_checkouts.sql`

```
alter table billing_checkouts
  add column provider text not null default 'lemonsqueezy'
    check (provider in ('lemonsqueezy','mmpay')),
  add column provider_order_id text,
  add column amount int,
  add column currency text;
create unique index billing_checkouts_provider_order
  on billing_checkouts(provider, provider_order_id)
  where provider_order_id is not null;
```

`subscription_id` stays nullable and is simply never written for `mmpay` rows.
`variant_id` is `not null` today and has no meaning for MMQR, so MMQR rows store
`'mmpay:1'` / `'mmpay:12'` — a readable sentinel rather than a schema change
that would ripple into the Lemon Squeezy validation.

Two new RPCs, both `security definer`, both revoked from `public,anon,
authenticated` and granted to `service_role` only, matching 0097's footer:

- **`reserve_mmpay_checkout(p_shop_id, p_owner_user_id, p_months)`** — takes the
  same `shop_subscriptions` row lock and the same open-checkout count as
  `reserve_gateway_checkout`, verifies `account_shop_role(...) = 'owner'`,
  rejects `months not in (1,12)`, derives the amount from the months, and
  inserts with `provider='mmpay'` and `checkout_expires_at = now() + <the MMQR
  TTL from §11 Q2>`. Returns the same `{reserved, checkout}` shape so the Edge
  Function's existing two-attempt loop needs no new shape.
- **`fulfill_mmpay_payment(p_checkout_id, p_order_id, p_amount)`** — locks in the
  same order (`shop_subscriptions` then `billing_checkouts`), refuses a row whose
  `provider` is not `mmpay`, refuses an order id that conflicts with one already
  stored, re-checks `amount` against `months`, re-checks owner role, stamps
  `provider_order_id` and `closed_at`, then calls
  `renew_shop_subscription(shop_id, months, 'mmpay:order:'||p_order_id)`.

Idempotency comes for free and in two layers: `shop_subscription_payments` keys
on the payment id, so a replayed webhook returns `duplicate: true` and grants
nothing, and the partial unique index makes a second row with the same order id
impossible. MMPay's documented duplicate deliveries are therefore a no-op rather
than a second month.

**Decision required (§11 Q5): the three `mmpay_*`-named columns on
`license_requests`.** Migration 0069 added `mmpay_order_id` and
`mmpay_expires_at` in anticipation of exactly this feature, under the *old*
key-minting licence model. Under this design MMQR never touches
`license_requests`, so those two columns will be permanently empty columns
wearing the name of a feature that writes elsewhere — the kind of thing that
costs an hour the next time someone debugs a payment. Recommendation: drop them
in 0098 and remove `mmpay_expires_at` from `handleReceipt`'s select, the
`RenewalReceipt` model and its tests. `payment_status` stays; it is live.

## 6. Edge Functions

### `storefront` — two new actions

Both sit beside `create_checkout` and reuse `billingOwner` / `billingShops`
verbatim, so authentication, shop-ownership scoping and the 401/403 shapes are
not reimplemented.

**`create_mmqr`** — body `{shop_id, plan}`.

1. `billingOwner` → 401, shop not in `billingShops` → 403, bad plan → 400.
2. `mmpayTestMode()` throws or secrets missing → 503 `checkout_unavailable`.
3. The same two-attempt reservation loop as `handleCheckout`. On a pre-existing
   open row the loop does something `handleCheckout` cannot: **because an MMQR
   order has a queryable terminal state, re-query it.** Terminal failed, expired
   or cancelled → `close_gateway_checkout` and retry the reservation. Already
   paid → fulfil it right there and return success, which self-heals the
   "customer paid, webhook never arrived" case that is otherwise a Viber message.
   Still pending → 409 `checkout_in_progress`. An open row belonging to the
   *other* provider returns the existing `subscription_already_exists` / 409.
4. Create the order against MMPay with our own checkout id as the merchant
   reference and `AbortSignal.timeout(15000)`, as every outbound call in this
   codebase does.
5. Persist `provider_order_id` and the QR payload; return `{qr, order_id,
   expires_at, amount}` to the page.

A 4xx from MMPay closes the reservation (no payable artifact was issued); a
timeout or 5xx **keeps** it, because an unknown outcome plus a retried POST is
how you end up with two payable QRs bound to one shop. That asymmetry is
`handleCheckout`'s and is deliberately copied.

**`mmqr_status`** — body `{shop_id, order_id}`, owner-authenticated. Re-queries
MMPay, fulfils on a verified paid status, and returns `{status, expires_at,
expires_in}`. This is what the page polls, and it is what makes the feature
correct when the webhook is late rather than merely when it is on time.

### `mmpay_webhook` — new function

Deployed with `--no-verify-jwt` (MMPay cannot present a Supabase JWT), which is
the one deployment detail easiest to forget and the one that makes every
callback 401 if missed.

Shape follows `lemonsqueezy-webhook` closely: POST only, read the raw body
first, verify the signature (§11 Q1) before parsing, ignore non-payment events
with `{ok: true, ignored: <event>}`, resolve the `billing_checkouts` row by our
own reference and fall back to `provider_order_id`, re-query the MMPay API,
assert mode / merchant / amount / currency, then call `fulfill_mmpay_payment`.
Refund and chargeback events are **recorded and alerted, not auto-reversed** —
clawing back a term automatically would log a working shop out mid-sale, and
the existing 14-day grace already absorbs a disputed payment safely.

### Secrets

`MMPAY_BASE_URL`, `MMPAY_MERCHANT_ID`, `MMPAY_API_KEY`, `MMPAY_WEBHOOK_SECRET`,
`MMPAY_TEST_MODE`. Service-role side only; the browser never sees any of them.
Never committed — the anon key remains the only key the client holds.

## 7. The `/renew` page

`renew_request_page.dart` already has the exact structure this needs: a
plan `SegmentedButton`, a server-reported `_cardPayment` capability flag that
hides the card option when the server cannot honour it, and a manual
KBZPay/WavePay block below. MMQR becomes a third block between them, shown only
when `list_billing_shops` reports a new `mmqr_payment: true` alongside the
existing `card_payment` — the server decides what is offered, as it already does.

Flow: owner signs in, picks the shop and plan, presses **Pay with KBZPay /
WavePay / AYA Pay** (MMQR covers KBZPay, WavePay, AYA, CB, A+, MAB, UAB, Yoma,
CTZ — the copy names the common three and says "and other MMQR banks" rather
than listing nine). A QR appears with the amount, a countdown to
`expires_at`, and a scan-with-your-banking-app instruction in both languages.
The page polls `mmqr_status` every four seconds, with the interval backing off
after the first minute. On paid: the existing `RenewalReceiptView` success
state, the new expiry date, done. On expiry: the QR greys out and a "Start
again" button returns to step one. On any failure the manual transfer block is
still right there on the same page, which is the whole reason for keeping it.

Mobile app: **no change**. `license_screen.dart` gates its purchase UI behind
`kCommerceUiEnabled` and that stays the boundary.

New i18n keys go into `app_en.arb` *and* `app_my.arb` in the same change-set —
`i18n_parity_test.dart` fails otherwise. The Myanmar strings are the primary
ones here; this is a Myanmar-only payment rail and most users of it will never
read the English.

## 8. Admin console

MMQR payments land in `billing_checkouts`, not `license_requests`, so the
console's Requests tab will not show them and the owner-facing story would be
"the money arrived but the console shows nothing". Two things close that:

- `renew_shop_subscription` already writes `shop_subscription_payments` with
  `payment_id = 'mmpay:order:<id>'`, so the payment is auditable by prefix.
- The console's per-shop view gains a Payments section listing those rows with
  provider, amount and date — one read, no new write path.

A paid-but-unfulfilled MMQR (payment verified, `renew_shop_subscription` threw)
must be **findable**, not silent: the same reasoning that gave 0069 its "Paid ·
needs key" pill. A `closed_at is null and provider_order_id is not null` filter
is that query.

## 9. Tests

- `supabase/functions/tests/mmpay_test.ts`, beside `account_billing_test.ts`,
  covered by CI's `deno check`: signature rejection; replayed webhook grants one
  month not two; amount mismatch refuses; wrong merchant refuses; sandbox
  payload against production mode refuses; non-payment event ignored; late
  webhook after a successful `mmqr_status` fulfilment is a no-op.
- SQL: two open checkouts for one shop impossible across *both* providers; an
  MMQR while a live Lemon Squeezy subscription exists is refused; `months=12`
  with a one-month amount refuses; expired-then-reserved-again works.
- Dart: the page shows no MMQR block when the server says `mmqr_payment: false`;
  countdown-expired state; poll-to-paid transition; manual block still reachable
  after an MMQR failure.
- `i18n_parity_test.dart` and `conventions_test.dart` pass unchanged — note the
  latter bans bare `functions.invoke`, so every new call uses `invokeBounded`.

## 10. Ripple-effect check (per CLAUDE.md)

- `grep -rn 'billing_checkouts' lib supabase` before writing: `handleCheckout`,
  `lemonsqueezy-webhook`, `reserve_gateway_checkout`, `close_gateway_checkout`,
  `fulfill_gateway_payment`. Each must be re-read against a non-null `provider`;
  `reserve_gateway_checkout`'s open-count query must start counting MMQR rows
  (that is the point) and `fulfill_gateway_payment` must refuse a non-Lemon-
  Squeezy row rather than quietly fulfil one.
- No Drift table, no `schemaVersion` bump, no sync mapper: this is all
  server-side, as 0069 was.
- No `SettingsRepository` key, so the device-vs-shop scope trap does not apply.
- `provider_invalidation_test.dart` unaffected — no local provider folds these
  tables. The app learns about a new expiry through its existing entitlement
  receipt refresh, which already handles a term changing underneath it.
- `shop_subscriptions.revision` increments on renewal, so previously issued
  `AIOE1.` receipts are superseded exactly as they are for a card renewal.

## 11. Open questions — answer from the sandbox before writing code

1. ~~**Does MMPay sign its webhooks, and how?**~~ **Answered — §13.1.**
   HMAC-SHA256 hex over `` `${nonce}.${rawBody}` `` keyed with the secret key,
   in `X-Mmpay-Signature` with `X-Mmpay-Nonce`. Their own verifier is neither
   timing-safe nor replay-checked; ours is both.
2. ~~**MMQR order TTL**~~ **Not disclosed, and the design no longer depends on
   it — §13.5.** Our own 15-minute window drives the page; MMPay's `status`
   stays the authority. Still worth asking support for the real number.
3. ~~**Transaction-status endpoint**~~ **Answered — §13.4.** `POST
   /payments/get` returns a distinguishable terminal `status` plus `appId` and
   `amount`, but **no `currency`**, and `SUCCESS` + `TOUCHED` is a re-scan, not
   a second payment. §4's assertion list is corrected accordingly.
4. **Sandbox without KYC — still open.** Can an Application be created and
   `sandbox-create` exercised while KYC is PENDING? `KA0002` ("API Key Not
   'LIVE'") suggests keys carry an activation state, so a sandbox key may well
   be issued immediately and only live keys gated. The console confirms KYC is
   PENDING with **zero applications**, and the answer is behind the Create
   Application form — see §14.4.
5. **Drop the stale `license_requests.mmpay_*` columns in 0098?** Recommended
   yes (§5).
6. **Who absorbs the 100 MMK?** Recommended: we do. Advertising 20,100 MMK to
   save 100 is not a saving.
7. **NEW, and now the top risk: is egress IP whitelisting mandatory?** §13.6,
   §14.4.
   Supabase Edge Functions have no static egress IP. An unauthenticated probe
   showed the IP gate does not fire before the bearer-token gate, which is
   encouraging but not proof. If whitelisting is required per application, this
   design does not run on Edge Functions without a fixed-address proxy. Check
   this **before** paying the activation fee.
8. **Is `PaymentResponse.url` a hosted payment page?** §13.4. If so it is a
   better mobile path than rendering the EMVCo string ourselves.
9. **Settled by §14.3, no longer open: the payment page's compliance
   requirements** — MMQR logo, MMK-only pricing, the exact string "Payment
   powered by myanmyanpay", a visual timer, a Download QR button, refresh-safe
   cached order state, and an explicit Cancel. §7 is revised accordingly and a
   `cancel_mmqr` action is added to §6.

## 12. Sequencing

Nothing here needs the 120,000 MMK activation until the final step, and the
first step is not code.

1. **Decide Individual vs Company on the KYC form before submitting.** The
   console states that after KYC is requested or approved, profile and banking
   details cannot be edited without contacting support. The form currently shows
   Merchant Type **Individual** with business name "AIO business", while the
   2026-08-25 account was NNK Company. If invoices or tax receipts should carry
   the company, that choice is made now or it is made through support later.
   Settlement is bank-account only, KBZ or AYA; a KPay wallet cannot receive it.
2. Answer the remaining §11 questions — **Q7 (IP whitelisting) first**, since a
   yes invalidates the Edge Function architecture, then Q4 and Q8.
3. Migration 0098 and the two RPCs, with the SQL tests.
4. `create_mmqr` / `mmqr_status` / `mmpay_webhook`, with `mmpay_test.ts`.
5. The `/renew` block and its i18n, against sandbox.
6. Submit KYC, pay activation, flip to production secrets, test one real 20,000
   MMK renewal end to end, reconcile it against the MMPay dashboard and the
   settlement two business days later.
7. `PROJECT_SPEC.md` §12 changelog entry in the same change-set as the code.

## 13. Protocol findings (2026-10-05)

Sources: `docs.myanmyanpay.com/api/`, `docs.myanmyanpay.com/system/`, and the
published source of `mmpay-node-sdk@1.1.4` (`src/index.ts`, `src/types.ts`).
One unauthenticated reachability probe was sent to the sandbox handshake
endpoint; no credentials, no account state touched.

### 13.1 Signature scheme — Q1 answered

```
stringToSign = `${nonce}.${bodyString}`
signature    = HMAC_SHA256(secretKey, stringToSign) as lowercase hex
```

Sent both ways in `X-Mmpay-Signature`, with the nonce in `X-Mmpay-Nonce`.
Outbound requests also carry `Authorization: Bearer <publishableKey>`. The
secret key signs; the publishable key identifies. Keys are environment-tagged
in their own value (`pk_test_` / `sk_test_` versus `pk_live_` / `sk_live_`).

For the inbound webhook this is the same construction over the **raw** request
body, which `lemonsqueezy-webhook` already reads correctly (`await req.text()`
before any parse). Deno's Web Crypto HMAC plus the existing
`timingSafeEqualHex` is a direct port.

Two gaps in MMPay's own verification that we must not inherit:

- `verifyCb` compares with `!==` on strings — not timing-safe. Ours stays
  timing-safe.
- **Nothing checks the nonce.** It is `Date.now()` and is never recorded or
  bounded, so a captured callback stays replayable forever. We reject a nonce
  outside a ±10 minute window, and the DB idempotency in §5 means a replay
  inside that window still grants nothing.

### 13.2 Every call is two round trips — handshake first

`/payments/handshake` (or `/payments/sandbox-handshake`) takes `{orderId,
nonce}` and returns a one-time `{token}`, which the real call then sends as
`X-Mmpay-Btoken`. So `create_mmqr` is two outbound calls and `mmqr_status` is
two as well. Each gets `AbortSignal.timeout(15000)` like every other outbound
call here, and the client-side bound on `create_mmqr` is sized accordingly —
`createCheckout` already carries a 75-second bound for exactly this reason.

The four endpoints, production and sandbox: `/payments/{,sandbox-}handshake`,
`/payments/{,sandbox-}create`, `/payments/{,sandbox-}get`,
`/payments/{,sandbox-}cancel`. Base host `https://ezapi.myanmyanpay.com`.
Rate limit 1000 req/min — our four-second polling is nowhere near it.

### 13.3 Do not use the npm SDK — write `_shared/mmpay.ts`

The protocol is four signed POSTs; the published SDK is about sixty lines of
value wrapped in defects we would be importing into the money path:

- **Every method swallows its errors** — `catch (error) { return error as any }`.
  A failed `pay()` returns an error object that is typed as a success. Our code
  would have to sniff the shape of a value the types say cannot happen.
- Because `handShake()` also swallows, a failed handshake leaves `#btoken`
  undefined and `pay()` proceeds anyway, sending `X-Mmpay-Btoken: undefined`.
- `verifyCb` is not timing-safe (13.1) and performs no nonce check.
- The shipped `test/payment.js` calls `MMPay.sandboxPay()`, a method that does
  not exist in `src/index.ts` — the package's own example cannot run, which is
  a fair measure of how much of it is exercised.
- `pay()` never forwards `currency`, though the REST API accepts it.
- Sandbox-versus-production is decided client-side by substring-matching
  `_test_` in the key. Our `mmpayTestMode()` server guard (§4) is unaffected by
  that and remains the authority.

So: a small `_shared/mmpay.ts` with `handshake`, `createPayment`, `getPayment`,
`cancelPayment` and `verifyCallback`, built on `fetch` and Web Crypto, errors
thrown rather than returned. Deno cannot use the Node-crypto SDK unmodified in
any case.

### 13.4 Status model — Q3 answered, with two corrections to §4

`POST /payments/get` returns `{appId, orderId, amount, vendor, method,
customMessage, callbackUrl, callbackUrlStatus, callbackAt, status,
disbursementId, disStatus, condition, createdAt, transactionRefId,
vendorQrRefId, qr}`.

`status` is `PENDING | SUCCESS | FAILED | REFUNDED | CANCELLED | EXPIRED` —
terminal states are distinguishable, which is what §4's re-query and §6's
self-healing reservation loop both depend on. `condition` is `PRISTINE |
TOUCHED | EXPIRED | DIRTY`.

Two corrections:

1. **The `get` response carries no `currency`.** §4's assertion list splits:
   on `get` we assert `appId` is ours, `orderId` is the one bound to this
   checkout, and `amount` equals the expected amount; `currency == "MMK"` is
   asserted on the callback body (which does carry it) and is fixed at
   creation anyway.
2. **`SUCCESS` + `condition: TOUCHED` means the QR was scanned again, not that
   a second payment happened.** The SDK routes that combination to
   `onHeartbeat` rather than `onTxSuccess`, so an integration that listens only
   for success would never grant the month on a re-scanned QR. We ignore
   `condition` for the grant decision, treat any `SUCCESS` as paid, and let the
   §5 idempotency make repeats free. This is precisely the trap the docs mean
   by "duplicate delivery".

`PaymentResponse` also carries a `url` alongside the EMVCo `qr` string. If that
is a hosted payment page it is a simpler mobile path than rendering the QR
ourselves — confirm in sandbox (Q8).

### 13.5 QR lifetime — Q2 is not answerable, so the design stops depending on it

There is an `EXPIRED` status, an `EXPIRED` condition and an `onTxExpire` event,
but **no expiry timestamp in any response or callback, and no documented TTL.**
Asking support is worth doing, but the design should not rest on the answer.

Revised: `checkout_expires_at` is **ours**, set to a deliberately conservative
15 minutes, and the page counts down against it. MMPay's `status` remains the
only authority on whether an order is actually dead — the reservation loop in
§6 re-queries before closing a row, so a QR that outlives our countdown is
reconciled correctly rather than abandoned, and one that dies early is caught
on the next poll. Our window only decides when the page offers "start again".

`orderId` is ours and must be unique per attempt forever: use the
`billing_checkouts` row id, and let a retry create a new row rather than
reusing an expired order id.

### 13.6 New blocker found — egress IP whitelisting (Q7)

Error `KA0005` is "IP Not whitelisted". **Supabase Edge Functions have no
static egress IP**, so if whitelisting is mandatory per application, this
design cannot run on Edge Functions at all and would need a proxy with a fixed
address — a materially different piece of work that should be known now and not
after the activation fee is paid.

One unauthenticated POST to `/payments/sandbox-handshake` from an ordinary
internet host returned `401 {"mmpayErrorCode":"KA0001"}` — bearer token
missing. The IP gate did **not** fire first, so whitelisting is at least not
enforced pre-authentication. That is encouraging but not conclusive: it may
simply be a per-application setting that is off by default. Confirm in the
console before anything else (Q7).

`KA0002` is "API Key Not 'LIVE'", which implies keys carry an activation state
of their own — probably the thing KYC gates, and the likely shape of the answer
to Q4.

## 14. Merchant-console findings (2026-10-05)

Read-only pass over `developers.myanmyanpay.com` with the owner's own signed-in
session. Nothing was created, submitted or changed. The Create Application form
was **not** opened (see §14.4), so Q4 and Q7 remain open.

### 14.1 Account state

Dashboard: **KYC STATUS PENDING**, available balance 0 MMK, zero transactions,
**zero applications**. Applications list is empty, so no API keys exist yet and
the Sandbox page renders blank — it appears to need an application first.

The dashboard carries a second balance bucket, **"SECURITY CHECK IN
PROGRESS"**, alongside "AVAILABLE BALANCE". Settlement is therefore not simply
"T+2 to your bank"; some portion can be held pending review. It does not change
this design, but it is the kind of thing worth knowing before telling a
customer their renewal has settled.

MyanMyanPay is a division of **Myantel Co., Ltd** — useful when the KYC form
asks who the counterparty is.

### 14.2 The storefront verdict is now prohibited in writing, by name

Rules & Guidelines, "Platform Fund Holding Restriction":

> Platforms acting as intermediaries (e.g., marketplaces, aggregators, SaaS
> platforms) are strictly prohibited from holding funds on behalf of their
> sub-merchants using our infrastructure.

— unless the platform holds a CBM regulatory allowance or a money-transmitter
permit verified by MMPay compliance. "Mandatory KYC Onboarding" adds that
shadow onboarding is banned, every business processing through the APIs needs
its own verified profile, and third-party routing of unverified merchant
payments means immediate suspension.

This names our exact category — a SaaS platform — and closes the storefront
question permanently. It does **not** touch this design: collecting our own
subscription revenue from our own customers is an ordinary merchant activity,
not fund-holding for sub-merchants.

### 14.3 Mandatory UI/UX rules — these change §7

The guidelines impose compliance requirements on the payment page itself.
Four of them are things the design did not have:

| Rule | Effect on `/renew` |
| --- | --- |
| MMQR logo shown; neither logo nor QR tampered with | Render the EMVCo string unmodified, with the MMQR mark |
| **MMK only** — foreign currencies may not be displayed | The MMQR block shows 20,000 / 200,000 MMK and nothing else. The Lemon Squeezy card option prices in USD, so the two must not be visible in the same payment surface — the card block collapses while an MMQR order is live |
| Exact text **"Payment powered by myanmyanpay"** | Verbatim, untranslated, under the QR |
| **A visual timer is required** | The §13.5 countdown is now mandatory UI, not a nicety — which also settles the question of what to show when no TTL is published |
| **A working "Download QR" button is required** | New. `storefront_download.dart` already has the web-only download pattern to follow |
| Returning from the banking app must not refresh the page; a refresh must restore the cached order and QR | The page keeps the order id and QR locally and restores them on load, with `mmqr_status` as the server-side source of truth |
| **No new transaction unless the user explicitly cancels the active one** | Matches the one-open-checkout guard in §3 exactly — but it also requires a user-facing **Cancel** button, which the design did not have |

**New requirement: a cancel path.** `POST /payments/{,sandbox-}cancel` takes
`{orderId}` and returns `CANCELLED`. Add a `cancel_mmqr` action that calls it
and then `close_gateway_checkout`, so the owner can abandon a QR and start
again — switching plan from monthly to yearly, say. Without it the guidelines'
"explicitly cancels" clause has nothing to hang on and the owner is stuck
behind their own 15-minute window.

### 14.4 Q4 and Q7 could not be answered read-only

Both answers live behind **Create Application** — the form is where a webhook
URL and any IP allow-list would be configured, and where it becomes visible
whether a `pk_test_` / `sk_test_` pair is issued while KYC is PENDING. Creating
an application changes the account, so it was not done. It needs either the
owner's own click or their explicit go-ahead.

What to look for on that form, in one pass:

1. Is there an **IP allow-list / whitelist field, and is it required?** (Q7 —
   the one that can invalidate the Edge Function architecture.)
2. Are **sandbox keys issued immediately** while KYC is PENDING, or does the
   form refuse? (Q4.)
3. Is the **webhook/callback URL** configured per application, or only passed
   per payment as `callbackUrl`? (Both appear in the API; which one is
   authoritative decides whether the webhook URL is config or code.)
4. Any **QR TTL** setting (Q2) and whether `PaymentResponse.url` is a hosted
   page (Q8).

## 15. Create Application answers Q7, Q4, Q3 and Q2 (2026-10-06)

The owner gave the go-ahead to open the Create Application form and test. An
application now exists on the merchant account:

| | |
| --- | --- |
| App Name | `All In One POS` |
| App ID | `MM57179826` (auto-generated, read-only) |
| Console id | `6ac479c7c2113c7d8c380636` |
| Integration Type | `SDK_SERVER` — "Server to Server (SDK)" (the other option is `SDK_BROWSER`) |
| Application Website | `https://shop.allinonepos.app/renew` — labelled "For Compliance Review" |
| Sandbox + Production Webhook URL | `https://gnikispsurwrmkspuisj.supabase.co/functions/v1/mmpay-webhook` (not deployed yet) |
| Status | `DEVELOPMENT` |

The row has a delete action, so this is reversible.

### 15.1 Q7 — IP whitelisting is **optional**. The architecture holds.

This was the top risk: Supabase Edge Functions have no static egress IP, and a
mandatory allow-list would have forced a fixed-address proxy. The form's section
is headed **"Security Whitelisting — OPTIONAL PROTECTION"** and contains *Domain
Whitelist (For Browser SDK)* and *IP Whitelist*, **neither marked required**,
both free-text and left empty. The application saved with both blank. Edge
Functions are a valid host for this integration; `KA0005` ("IP Not whitelisted")
only fires for merchants who opt in. **Q7 closed, and the activation fee is no
longer gated on it.**

### 15.2 Q4 — sandbox is available while KYC is PENDING

The application was created with KYC still `PENDING`, and the Sandbox
Environment block is fully editable while Production carries a **LOCKED** badge
and the text that production keys require passing KYC *and* a compliance review.
The app page offers **Generate Sandbox Keys** — not yet clicked, because the
secret belongs in the owner's hands and then straight into Supabase Edge
Function Secrets, never into a transcript. **Q4 closed: sandbox does not wait on
KYC.**

### 15.3 Q3 — the webhook URL is per-application configuration, not per-payment

Separate **Sandbox Webhook URL** and **Production Webhook URL** fields, both
required at creation. So the callback endpoint is configuration, not something
the payment call has to carry; a per-payment `callbackUrl` may still override,
but the design can rely on the configured one.

### 15.4 Q2 — the 15-minute window is MMPay's own rule, not our guess

§13.5 picked 15 minutes conservatively because no TTL was documented. The
console's compliance rules **mandate exactly that**: "15 mins အချိန်ကိုက်
(timer) ကို ထင်ရှားစွာ ထည့်သွင်းရမည်" — a visible 15-minute timer is required to
pass compliance. The design's own window is now also the published requirement.

### 15.5 New findings

- **Production go-live runs through Discord**, not a form: "complete your
  integration in Sandbox and request a review via Discord"
  (`discord.com/invite/pGQ5gQbPpd`). So the sequence is sandbox integration →
  KYC → Discord review → production keys.
- **Event Subscriptions** list exactly `PENDING, SUCCESS, FAILED, REFUNDED,
  CANCELLED, EXPIRED` — confirming §13.4's status enum from the console side.
- **Alert Notifications** can push transaction updates to Discord, Slack or a
  Telegram bot. A Telegram or Discord alert on `SUCCESS` and `FAILED` is a cheap
  second channel for the paid-but-webhook-lost case, independent of our own
  re-query.
- The **Sandbox Transactions** page (`/sandboxs`) lists test payments with a
  **CALLBACK** column and per-row actions, so webhook delivery can be inspected
  and (apparently) replayed from the console during integration.
- The MMQR logo required by the compliance rules is downloadable from the
  console at `/MMQR_Logo.png`.

### 15.6 Still open

- **Q8** — whether `PaymentResponse.url` is a hosted payment page. Nothing on
  the application form settles it; it needs a sandbox call.
- **Q5** (drop the stale `license_requests.mmpay_*` columns) and **Q6** (who
  absorbs the 100 MMK) are decisions, not discoveries — recommendations in §11
  stand.
- Fees, settlement timing and the "SECURITY CHECK IN PROGRESS" balance bucket
  (§14) are unchanged and still need the merchant's own enquiry.
- **Next action is the owner's**: click *Generate Sandbox Keys*, and put the
  secret into Supabase Edge Function Secrets as `MMPAY_SANDBOX_SECRET_KEY`
  (publishable key as `MMPAY_SANDBOX_PUBLIC_KEY`). Code can be written before
  that; only the live sandbox call needs it.

## 16. What was built (2026-10-06)

Written ahead of the sandbox key, so only the live call is still waiting on it.

| File | What it is |
| --- | --- |
| `supabase/migrations/0098_mmpay_checkouts.sql` | `provider` / `provider_order_id` / `amount` / `currency` on `billing_checkouts`, the partial unique index, `reserve_mmpay_checkout`, `close_mmpay_checkout`, `fulfill_mmpay_payment`, and the Q5 drop of `license_requests.mmpay_*` |
| `supabase/functions/_shared/mmpay_mode.ts` | the server-decides-the-mode guard, plus `mmpayConfig()` |
| `supabase/functions/_shared/mmpay.ts` | handshake / create / get / cancel / `verifyCallback`, on fetch + Web Crypto |
| `supabase/functions/mmpay-webhook/index.ts` | the callback endpoint |
| `supabase/functions/storefront/index.ts` | `create_mmqr`, `mmqr_status`, `cancel_mmqr`, and `mmqr_payment` on `list_billing_shops` |
| `supabase/functions/tests/mmpay_test.ts` | 11 Deno tests |
| `supabase/tests/mmpay_checkout_test.py` | 42 SQL tests |

### 16.1 Decisions taken while writing it

- **Secret names changed from §6.** `MMPAY_MERCHANT_ID` / `MMPAY_API_KEY` /
  `MMPAY_WEBHOOK_SECRET` were written before the key model was understood.
  MMPay issues a **pair** whose environment is baked into the value, and the
  same secret key signs outbound requests and inbound callbacks — so there is
  no separate webhook secret to hold. The set is now `MMPAY_APP_ID`,
  `MMPAY_PUBLISHABLE_KEY`, `MMPAY_SECRET_KEY`, `MMPAY_TEST_MODE`, and an
  optional `MMPAY_BASE_URL` override that must be https.
- **The key's own prefix never decides the mode.** `mmpayConfig()` checks the
  `_test_` / `_live_` tag *against* the mode the server decided and refuses a
  mismatch in both directions. The published SDK does the opposite — it decides
  sandbox-vs-live by substring-matching the key — which means a live key pasted
  into staging quietly starts taking real money. Covered by a test.
- **`REFUNDED` does not release a reservation.** It is terminal, but the money
  did arrive; releasing would offer a second QR for a term already granted.
  `isDead()` is `FAILED | CANCELLED | EXPIRED` only.
- **`fulfill_mmpay_payment` re-derives the price from the stored term** rather
  than comparing against the stored `amount`, so editing the reservation row
  cannot buy a year at a month's price. Tested directly.
- **The order id is the `billing_checkouts` row id**, so `create_mmqr` needs no
  second identifier and a retry takes a fresh row rather than reusing a dead
  order id.
- **The `/renew` page's Cancel is wired server-side** as `cancel_mmqr`, which
  re-queries before closing: cancelling an order that was in fact paid fulfils
  it instead of throwing the term away.

### 16.2 Not built yet

- **The `/renew` page (§7).** All six compliance requirements — untampered MMQR
  logo, MMK-only pricing, the verbatim "PAYMENT POWERED BY MYANMYANPAY", the
  15-minute visible timer, a working Download QR, and refresh-safe cached
  order/QR state — are page work and none of it exists.
- **Deployment.** `0098` is not pushed, no function is deployed, and
  `mmpay-webhook` must be deployed with `--no-verify-jwt` or every callback
  401s before the handler runs.
- **Q8** — whether `PaymentResponse.url` is a hosted page. The client already
  returns `url` alongside `qr` so the page can prefer it if it turns out to be
  one; a sandbox call settles it.

## 17. Sandbox proven, and three things the documents got wrong (2026-10-06)

Sandbox keys were generated from the console with **KYC still PENDING** — which
settles **Q4** for good — and `tool/mmpay_sandbox_probe.ts` drove our own client
through the full cycle against `ezapi.myanmyanpay.com`:

```
create  201  status PENDING, qr 150 chars
get     200  status PENDING, condition PRISTINE, appId MM57179826
cancel  200  status CANCELLED
get     200  status CANCELLED
```

Three mismatches between what was designed and what the API does. Each would
have been a deployed function that never worked:

### 17.1 `orderId` is capped at 32 characters

§13.5 said "use the `billing_checkouts` row id". A hyphenated UUID is 36
characters and the API answers
`body/orderId must NOT have more than 32 characters`. The row id now travels as
its **32 hex digits with the hyphens stripped** (`compactOrderId`) and is
expanded back on the way in (`expandOrderId`) — lossless, still unique per
attempt forever, and still ours rather than MMPay's.

### 17.2 The nonce must be in the signed **body**, not only the header

Sending it only as `X-Mmpay-Nonce` answers **`KA0003`**, an error code that
appears in no published document. The SDK source shows what the docs do not:
`handShake()`, `pay()`, `get()` and `cancel()` all put `nonce` **inside** the
body, with the same value as the header and as the signature — and the
handshake shares the nonce of the call it authorises. Fixed, and pinned by a
test that asserts body nonce equals header nonce for both legs.

### 17.3 The request bodies are validated strictly, and `currency` is not one of them

§13.3 noted the SDK never forwards `currency` though "the REST API accepts it".
It does not: the endpoints validate their bodies and the fields are exactly
`create {appId, nonce, amount, orderId, callbackUrl, customMessage}` and
`get`/`cancel` `{orderId, nonce}` — **no `appId` on get or cancel**. The
response carries `currency: "MMK"` by itself, so nothing is lost.

### 17.4 Q8 answered — there is **no** hosted payment page

`create` returns `{orderId, amount, currency, status, transactionRefId,
vendorQrRefId, qr}`. No `url`, in any response. The §7 page must render the
EMVCo MMQR string itself, which is also what the compliance rules assume
(untampered MMQR logo, working Download QR). `PaymentResponse.url` in the
type definitions is aspirational; the field is removed from our client.

### 17.5 Smaller observations

- `create` answers **201**, the others 200.
- The handshake token is a JWT bound to `{orderId, nonce}` with a **ten-minute
  expiry** — it is per-call, so there is nothing worth caching.
- `get` carries `callbackUrlStatus` (`PENDING` before delivery) and `disStatus`
  (`NONE` before disbursement) — both useful for reconciliation, neither
  documented in the console's own page.
- `cancel` answers without `appId` or `condition`; only `get` carries `appId`,
  which is where the merchant assertion lives, so that still holds.
- `condition` stayed `PRISTINE` through cancellation, confirming it tracks
  scanning rather than settlement.

### 17.6 Deployed

Migration 0098 is applied to production (`license_requests` was empty — both
dropped columns verified at 0 rows before pushing), `storefront` is at v46 and
`mmpay-webhook` at v2, deployed `--no-verify-jwt` and verified reachable
without a JWT. **No `MMPAY_*` secret is set on production**, so `mmpayConfig()`
refuses, the webhook answers `503 mmpay_not_configured`, and
`list_billing_shops` reports `mmqr_payment: false` — the feature is live in
code and dark in behaviour. The sandbox keys live only in the gitignored
`mmpay.local.json` on the owner's machine, because `mmpayTestMode()` throws on
the production host by design: sandbox money must never buy a real month.

## 18. The `/renew` MMQR surface (2026-10-06)

§7's page exists. All six compliance requirements are implemented in
`lib/storefront/mmqr_checkout.dart`, and each is asserted by a test in
`test/mmqr_checkout_test.dart` rather than left to whoever edits the widget
next — breaking one is not a cosmetic regression, it is losing the ability to
take money at all.

| Rule | Where | Test |
| --- | --- | --- |
| MMQR logo, untampered | `assets/branding/mmqr_logo.png`, downloaded from the console and shown with no recolour or crop | asserts the asset name is the one on screen |
| MMK only, no other currency beside it | the amount renders `20,000 MMK`; the page hides the SGD card option entirely while a QR is live | asserts no `SGD`/`USD`/`THB`/`JPY`/`$` appears |
| "PAYMENT POWERED BY MYANMYANPAY" verbatim | beneath the code, **not translated** — it is a brand string, not copy | asserted in English *and* Myanmar |
| QR never modified | the EMVCo payload goes to `BarcodeWidget` exactly as issued | decodes the widget's bytes and compares to the issued string |
| Visible 15-minute timer | a one-second ticker, turning into a warning colour under two minutes | asserts it is shown and that it counts down |
| Working Download QR | rasterises the on-screen `RepaintBoundary` to PNG and hands it to the existing web share/save path | asserts the button exists and is enabled while live |

Plus the two UX rules:

- **Refresh-safe.** `mmqr_store_web.dart` caches the live order in
  `localStorage` and the page restores it once the shop is known, so returning
  from a banking app — or a refresh — finds the same order and QR rather than
  issuing a second one. The cache is only a hint about *which* order to ask
  about; `mmqr_status` remains the authority. Every read and write is wrapped,
  so private browsing degrades to "works until you leave" rather than failing.
- **No second order unless the owner cancels.** The Cancel button really
  cancels at MMPay, and asks first — cancelling after paying is the expensive
  mistake, so the server re-queries and fulfils instead of discarding the term.

### 18.1 Behaviour worth knowing

- The page polls `mmqr_status` every four seconds (MMPay's limit is 1000/min).
  This is what makes a renewal land when the callback is late rather than only
  when it is on time.
- Switching shops clears a live order from the surface: an order belongs to the
  shop it was issued for and must never be shown against another.
- A status MMPay has not told us about is read as **pending**, never as
  finished — the page keeps waiting rather than telling an owner it is over.
- `REFUNDED` is terminal but is **not** treated as dead: the money did arrive,
  and offering a second QR for a granted term is worse than offering none.
- The widget runs a one-second timer, so `pumpAndSettle` never settles on it —
  its tests pump explicit frames.

### 18.2 Verified

Analyzer clean, **1,071** Flutter tests pass (17 new). The storefront web target
builds and `/renew` loads with no console errors, which is the only check that
exercises `dart:js_interop` and `web.window.localStorage` — the native test run
cannot compile that file at all. Layout checked at 390 px with no overflow.

**Not verified, and cannot be here:** a real scan-and-pay. The deployed project
holds no `MMPAY_*` secret, so the server reports `mmqr_payment: false` and the
card never appears; and `mmpayTestMode()` throws on the production host by
design. Seeing the surface against the live sandbox needs a tunnel to a local
function or a staging Supabase project.

## 19. A real callback, and the bug only a real callback could find (2026-10-06)

The console has a webhook simulator that §14 missed: **Sandbox → a transaction →
FIRE SUCCESS / FIRE FAIL**, which dispatches a genuine signed callback to the
order's `callbackUrl` and shows the outbound request and the inbound response.
A sandbox order was created with its `callbackUrl` pointing at a localtunnel
URL in front of a small Deno receiver running our own `verifyCallback`. No
Docker here, so the real function could not be served against a database; what
this proves is the signature path, which is the part that was never observed.

### 19.1 The signature construction is exactly right

Two real callbacks, and on both `expected == received`, byte for byte:

```
expected d83ff9665c5330ad86715ac3d292894d1059bef8d6e3185e72e49fb42dc460cc
received d83ff9665c5330ad86715ac3d292894d1059bef8d6e3185e72e49fb42dc460cc
```

§13.1's `HMAC_SHA256(secretKey, nonce + "." + rawBody)` as lowercase hex, read
out of the SDK source and never seen on the wire, is confirmed.

### 19.2 …and `verifyCallback` rejected both of them

`SIGNATURE VERIFIES: false`, with `nonce age NaNs`. **The inbound nonce is not
a timestamp.** Outbound, MMPay uses `Date.now()`; inbound, a real callback
carries `X-Mmpay-Nonce: e7c6d2d9c095aa69` — sixteen opaque hex characters. §13.1
assumed the two were the same thing, so the ±10-minute window did `Number(nonce)`
→ `NaN` → reject, and **the deployed webhook would have answered 401 to every
genuine callback MMPay ever sent**. Nothing in the documents, the SDK source or
the type definitions says this; only firing one does.

Fixed: the time window now applies **only** when the nonce actually looks like
epoch milliseconds, which keeps the protection if MMPay ever switches to one
without inventing a rule they do not follow. An opaque nonce must still be
8–64 hex characters, and anything else is refused. Replay is bounded by the
database instead, which is where it was always really bounded: the signature
covers `nonce.body`, the body carries the order id, that order id is uniquely
indexed and keyed by payment id — so a captured callback can only re-deliver
its own order, which grants nothing twice, and it can never be retargeted at
another order because changing a byte invalidates the signature.

Re-fired after the fix: **`SIGNATURE VERIFIES: true`**.

### 19.3 Other things the wire showed

- **A callback fires on creation too**, not only on settlement: the first
  delivery was `status: PENDING`, unprompted. Our webhook already answers
  `{ok: true, ignored: "PENDING"}` to those, which is what stops MMPay retrying.
- The callback body is **flatter than `get`**: `{orderId, amount, currency,
  vendor, method, status, condition, customMessage, vendorQrRefId,
  transactionRefId, callbackUrl}` — **no `appId`**, which is why the merchant
  assertion belongs on the re-query and not on the callback. It *does* carry
  `currency: "MMK"`, as §13.4 said.
- A simulated success arrives with `vendor` and `transactionRefId` both set to
  `MMPAY_MANUAL`, so a sandbox-only sentinel exists and must not be special-cased.
- MMPay's dispatcher is Bun (`user-agent: Bun/1.4.2`) and it reads the response
  body, so answering 200 with JSON is enough to mark the delivery complete.

### 19.4 What is still unproven

The webhook was exercised as a signature verifier, not end to end: no local
database meant no `fulfill_mmpay_payment`, so granting a term from a real
callback has still never happened. That needs Docker and `supabase start`, or a
staging project. The deployed `mmpay-webhook` carries the fix (v3) and remains
dark — no `MMPAY_*` secret is set on production.

## 20. End to end: a real callback granting a real month (2026-10-07)

The last gap closed. `fulfill_mmpay_payment` has now run from a genuine
MyanMyanPay callback, against a real Postgres, and the shop's term moved.

### 20.1 Setup

Docker via **colima** (no admin password, unlike Docker Desktop), then
`supabase start`. Two things had to be worked around and both are recorded in
`supabase/config.toml`:

- **`vector` cannot start under colima.** It bind-mounts the Docker socket, and
  a Lima VM cannot mount that path. `[analytics] enabled = false` removes it;
  nothing in this project uses local analytics.
- **`postgres-meta` fails with `exec format error`** on this machine even
  though its image is arm64. It only serves Studio, so it is excluded along
  with everything else this test does not need:
  `supabase start -x studio,postgres-meta,imgproxy,storage-api,realtime,mailpit,edge-runtime,logflare,vector,supavisor`.
  Note the name is `postgres-meta`; `pg_meta` is silently *not* a valid
  exclusion and the CLI only warns.

Only `mmpay-webhook` was served, on its own port with `deno run`, rather than
`supabase functions serve` — that exposes the whole local API through Kong on
54321, and the tunnel in front of it is public. A localtunnel URL was the
order's `callbackUrl`.

### 20.2 The run

Shop `a` seeded through `create_account_shop`, **plan `free`, expires 1970**.
`reserve_mmpay_checkout` took a row; an MMQR order was created against the
sandbox with that row's id, compacted. Then **FIRE SUCCESS** in the console:

| | before | after |
| --- | --- | --- |
| `shop_subscriptions` | `free`, expires 1970-01-01 | **`monthly`, expires 2026-11-06** |
| `shop_subscription_payments` | 0 rows | **1** — `mmpay:order:995e377d…`, months 1 |
| `billing_checkouts` | open, no order id | order id stamped, **closed** |

The webhook verified the signature, re-queried `/payments/get`, asserted the
merchant and the order, and called the RPC. One month, from `now()`, because
the shop had no live term to extend.

### 20.3 Idempotency, demonstrated rather than asserted

Fired a second time. MMPay's own inspector shows what came back:

```json
{ "ok": true, "duplicate": true, "expires_at": "2026-11-06T16:32:12.411144+00:00" }
```

`expires_at` identical to the first grant, `shop_subscription_payments` still
one row. MMPay's documented duplicate deliveries buy nothing — which until now
was only a claim about a unique index.

### 20.4 What this does and does not prove

Proven: signature verification on a real callback, the re-query, the merchant
and amount assertions, `fulfill_mmpay_payment`, the term arithmetic, and
idempotency across redelivery. Also that **every migration 0001–0098 applies
cleanly to a fresh database** — the local stack builds one from scratch.

Not proven: an actual scan-and-pay from a banking app (sandbox has no payer),
and `create_mmqr` / `mmqr_status` end to end, which need an owner JWT through
Kong rather than a direct RPC. Neither is on the path this test was for.

Production is untouched throughout and remains dark: no `MMPAY_*` secret is set
there, so `mmqr_payment` is false and the webhook answers 503.
