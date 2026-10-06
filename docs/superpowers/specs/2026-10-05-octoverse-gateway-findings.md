# Octoverse Gateway (MPSS) — evaluation findings

Date: 2026-10-05 (Asia/Singapore)
Status: research only. No code, no migration, no secrets, nothing deployed.
Companion to `2026-10-05-mmpay-mmqr-licence-payments-design.md` — same problem
(automatic local payment for `/renew`), different provider.

Method: signed-in read of `developer.octoverse.com.mm` with the owner's own
session, plus one **UAT** token request (no money, no production credentials).
One project was created at the owner's explicit instruction: **"All In One POS",
Redirect API Integration**.

## 1. Who this is

MPSS (Myanmar Payment Solution Services, `mpss.com.mm`) is the company;
**Octoverse Gateway** is its payment product. The MPSS site's "Developer Zone"
points straight at `developer.octoverse.com.mm`. A public demo storefront exists
at `demo.octoverse.com.mm`.

## 2. Integration types

The console offers Direct API, **Redirect API** and WordPress. Redirect is the
right one for `/renew`: Octoverse hosts the payment page, so none of the MMQR
compliance UI (logo, timer, Download QR, "powered by" string) that §14.3 of the
MMPay design put on us applies here — their page carries it.

## 3. Protocol (from the console's own reference)

Base URL (UAT): `https://test.octoverse.com.mm/api/payment`. Production
credentials and URL are issued by the Octoverse team after setup — **not
self-serve**.

Credentials are a triple: `merchantID`, `secretKey` (signs), `dataKey`
(decrypts). All provided by Octoverse; the console shows ours masked.

**Request payment token** — `POST {base}/auth/token`, body `{"PayData": <JWT>}`
where the JWT is HS256-signed with `secretKey` over
`{merchantID, invoiceNo, amount, currencyCode, frontendUrl, backendUrl,
userDefination1..3}`. `currencyCode` accepts **MMK and USD**. Response
`{respCode, respMsg, data}`; `data` is a JWT whose payload carries
`paymentToken`, `accessToken` and the hosted `paymentUrl`.

**Check payment status** — `POST {base}/auth/paymentInQuery`, `payData` = JWT of
`{merchantID, invoiceNo}`. The response `data` is **AES-128-ECB** encrypted with
`dataKey`. This is the re-query endpoint our trust model requires: the callback
stays a hint, this is the authority.

**Callback** — `backendUrl` is passed **per payment**, not configured per
project, so the webhook URL is code, not console config. Flow confirmed by their
sequence diagram: token → redirect to hosted page → customer pays in their
banking app → **backend callback** → frontend redirect to `frontendUrl` →
merchant calls Payment Query.

## 4. Live UAT test performed

`JWT Encode` → `Send Request` against `test.octoverse.com.mm`:

- First attempt returned `{"respCode":"0020","respMsg":"Duplicate Invoice No."}`
  — i.e. **authentication and signing already succeed**, it only rejected a
  re-used invoice number.
- With a fresh invoice (`AIOPOS2610051`, 1500 MMK) it returned
  `{"respCode":"0000","respMsg":"Success"}` plus a working
  `https://test.octoverse.com.mm/payment?itoken=…&ptoken=…` hosted page.

Two things follow, both of which were blockers on the MMPay side:

1. **UAT works with no KYC and no onboarding call.** (MMPay's equivalent, Q4,
   is still unanswered behind a form.)
2. **No egress-IP whitelisting at UAT.** The call left an ordinary residential
   browser IP and was accepted. This is the MMPay Q7 risk that would have
   invalidated running on Supabase Edge Functions. Still to confirm for
   production, but the architecture is not dead on arrival here.

## 5. Payment methods on the hosted page (UAT)

- **E-Wallet** — AYA Pay, WavePay and two others
- **QR Scan** — KBZPay, AYA Pay, WavePay, A+ Wallet, one more
- **Web Pay** — M-Pitesan, OK$, CTZPay, one more
- **Local Card** — MPU
- **Global Card** — Visa / Mastercard

That last row matters: **one integration covers both the local rails and
international cards**, so Octoverse could replace the Lemon Squeezy path rather
than sitting beside it. `currencyCode` accepting USD points the same way.

## 6. Still unknown — needs MPSS/Octoverse directly

1. Fees: setup, per-transaction, MDR %. Nothing published. (MMPay: 120,000 MMK
   + 100 MMK/txn + 0% MDR.)
2. Settlement bank, period, and whether funds can be held for review.
3. **Backend callback payload format and how it is authenticated** — the
   console documents the two outbound APIs but not the inbound callback. This
   is the one protocol gap and it sits on the money path.
4. Production onboarding: what KYC, what documents, Individual vs Company, how
   long, and whether production whitelists IPs.
5. Refund/chargeback handling.

## 7. What does not change

Storefront payments remain out of scope. Octoverse is an aggregator under the
same CBM/AML regime that MMPay spells out in writing (§14.2 of the MMPay
design): a SaaS platform may not hold funds for sub-merchants. This gateway is
for **our own licence revenue only**. Per-shop KPay/Wave number plus transfer
proof stays the storefront model.

The `billing_checkouts.provider` design (MMPay design §3, Option B) is
provider-neutral and holds unchanged if Octoverse is chosen instead of MMPay —
only the fulfilment function and the `_shared/<provider>.ts` client differ.
