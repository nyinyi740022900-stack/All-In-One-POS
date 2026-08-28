# Production-fix priority Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the locked 21 POS money/UI bugs plus the N1–N14 follow-up findings in waves, so cashiers stop losing kyat before we polish ledgers and the web shop.

**Architecture:** Each wave is independently shippable. Do not mix uncommitted CashTopUps (`0075`) into a store build until wipe + promote + `sync_force_apply` include `cash_top_ups`. Do not fold new finds into the locked 21 IDs — keep P1–P21 and N1–N14.

**Tech Stack:** Flutter / Drift / Riverpod, integer kyat `Money`, Supabase Edge Functions, EN+MY ARB + `flutter gen-l10n`.

**Spec:** Chat audit 28 Aug 2026; canvas `pos-payment-inventory-accounting-review.canvas.tsx` (locked 21 + this-pass N1–N14).

## Global Constraints

- Money is `int` kyat. No floats.
- i18n: every new string in `lib/l10n/app_en.arb` AND `lib/l10n/app_my.arb`, then `flutter gen-l10n`.
- Synced table changes: tables + schemaVersion + mapper + RLS migration (see CLAUDE.md).
- Ripple-effect check: grep every reader of a table/column you change.
- `PROJECT_SPEC.md` §12 changelog in the same change-set.
- `flutter analyze` clean + relevant tests before calling a wave done.
- Do not ship working-tree top-ups until `wipeSyncedData` deletes `cashTopUps`, `promoteShopIdentity` rewrites them, and `ALLOWED_TABLES` includes `cash_top_ups`.

---

## File map (waves touch these)

| Area | Files |
|------|--------|
| Discount pad | `lib/features/sell/checkout_sheet.dart` (`_AmountPadDialog._digit`) |
| Credit till / overpay / confirm | `lib/data/repositories/sales_repository.dart`, `lib/features/sell/checkout_sheet.dart`, `lib/features/cash/cash_session_repository.dart` |
| Order → sale | `lib/features/orders/orders_repository.dart`, `lib/features/orders/order_detail_sheet.dart` |
| Refund stock | `lib/data/repositories/sales_repository.dart` |
| Receipt owed | `lib/features/invoices/receipt_formatter.dart`, `lib/features/invoices/receipt_data.dart`, `lib/features/invoices/receipt_mapper.dart` |
| Balance Sheet cash | `lib/features/accounting/accounting_providers.dart`, `lib/features/accounting/cash_flow_calculator.dart` |
| Cash close UI | `lib/features/cash/cash_session_screen.dart` |
| License | `lib/features/staff/staff_ui.dart`, `supabase/functions/activate/index.ts` |
| Backup / wipe / promote | `lib/features/backup/backup_service.dart`, `lib/data/local/database.dart`, `lib/data/local/shop_data_transition_service.dart` |
| Force-apply | `supabase/functions/sync_force_apply/index.ts` |
| Storefront | `supabase/functions/storefront/index.ts`, `lib/storefront/storefront_page.dart` |

---

## Wave 0 — same day (cashiers lose money on every sale)

Ship these before any App Store build. No migration required except if you also finish 0075 (do not).

### Task 0.1: P20 Discount keypad (Critical)

**Files:** Modify `lib/features/sell/checkout_sheet.dart` `_AmountPadDialogState._digit` (~1129). Test: add `test/amount_pad_digit_test.dart` by extracting `_digit` math to a top-level `int appendPadDigits(int value, String d)` in the same file or `lib/features/sell/amount_pad.dart`.

- [ ] **Step 1:** Extract and test. Expected: `appendPadDigits(0,'1')==1`, `appendPadDigits(1,'0')==10`, `appendPadDigits(12,'5')==125`, `appendPadDigits(5,'00')==500`, `appendPadDigits(0,'0')==0`. Current formula `_value * d.length + int.parse(d)` fails these.
- [ ] **Step 2:** Implement `next = value * (d == '00' ? 100 : 10) + int.parse(d)`; reject if `'$next'.length > 10`.
- [ ] **Step 3:** Paid-amount `_padDigit` is string concat — do not change it.
- [ ] **Step 4:** `flutter test` the new test + `flutter analyze`. Changelog. Commit.

### Task 0.2: P2 + P3 + P16 Credit deposit, overpay, Confirm label

**Files:** `lib/data/repositories/sales_repository.dart` `finalizeSale`; `lib/features/sell/checkout_sheet.dart` Confirm button (~836) and `_SaleSuccess`.

- [ ] Write the deposit `Payments` row with the real tender (`cash` / wallet), remainder as credit — or require split (cash + credit). Never stamp a cash deposit as `method: 'credit'`.
- [ ] Reject `paid > total` on credit, or record excess as `changeDue` and show it on the success panel (`isCredit` must not hide change).
- [ ] Confirm button amount: if `_method == 'credit'` show `paid` (deposit), not `total`. Empty paid-now is 0 — label must not look like a full charge.
- [ ] Tests: `test/cash_session_test.dart` / `test/sales_repository_test.dart` — credit + 4000 cash deposit increases `computeExpectedCash` by 4000; paid 12000 on 10000 credit does not drop 2000.
- [ ] i18n if the button needs a “deposit” caption. Changelog. Commit.

### Task 0.3: P8 Refund phantom stock

**Files:** `lib/data/repositories/sales_repository.dart` `refundSale` / `_recordStockReturn`.

- [ ] Call `_recordStockReturn` only when original sale deducted tracked stock (`originalTrackedStock` / non-empty `productId`). Skip invoice-only and free-text lines.
- [ ] Test: enable `trackStock` after an invoice-only sale, refund → no `type=return` movement, `stock_levels.quantity` unchanged.
- [ ] Changelog. Commit.

### Task 0.4: P4 Order → sale `paid = total`

**Files:** `lib/features/orders/orders_repository.dart` `convertToSale`; `lib/features/orders/order_detail_sheet.dart` convert sheet; `lib/l10n/app_en.arb` + `app_my.arb` (`orderConvertHint`).

- [ ] Pass collected amount. COD + `paymentStatus != paid` → `paid: 0` (or credit remainder), not `itemsTotal + deliveryFee`.
- [ ] UI: amount field or default from `paymentStatus`; hint must say it records collection, not only “creates invoice”.
- [ ] Test: unpaid COD convert as cash → `Sale.paid == 0`, till expected cash unchanged.
- [ ] Changelog. Commit.

### Task 0.5: P19 Thermal receipt balance due

**Files:** `lib/features/invoices/receipt_data.dart`, `receipt_formatter.dart`, `receipt_mapper.dart`; ARB `receiptBalanceDue` / reuse `invoiceAmountDue`.

- [ ] Add `owed` (or print `invoiceAmountDue`) whenever remaining > 0, including `paid == 0` credit.
- [ ] Do not only print Paid/Change when `paid > 0`.
- [ ] Unit test formatter with credit 0 down and credit partial.
- [ ] `flutter gen-l10n`. Changelog. Commit.

---

## Wave 1 — before publish (wrong books / till close / security)

### Task 1.1: P1 Balance Sheet + Cash Flow include physical cash

**Files:** `lib/features/accounting/accounting_providers.dart` `balanceSheetProvider`; `lib/features/accounting/cash_flow_calculator.dart`.

- [ ] All-time cash asset = same ingredients as `computeExpectedCash` (cash payments + cash repayments + top-ups − till expenses − cash supplier payments + session float). Grep every `cashAndAccounts` reader.
- [ ] Test: 10_000 cash sale increases `cashAndAccounts` by 10_000; KBZPay-only sale does not.
- [ ] Changelog. Commit.

### Task 1.2: P17 Cash close expected fallback

**Files:** `lib/features/cash/cash_session_screen.dart` `_close` (~129).

- [ ] Disable Close while `expectedCashProvider` is loading or error. Never pass `openingAmount` as “Expected now”.
- [ ] Changelog. Commit.

### Task 1.3: P6 Snapshot closed-session expected cash

**Files:** `lib/data/local/tables.dart` `CashSessions`; `database.dart` schema bump + `onUpgrade`; `cash_session_repository.dart` `closeSession`; reports.

- [ ] Persist `expectedCashAtClose` (int) on close. Closed reports read the snapshot. Live recompute only for open sessions.
- [ ] Optional: refuse till-expense edit/delete whose `createdAt` falls in a closed window.
- [ ] Migration + mapper + RLS column if synced. Tests for close-then-edit-expense.
- [ ] Changelog. Commit.

### Task 1.4: P7 Lock payment-account opening balance

**Files:** `lib/features/accounts/payment_accounts_screen.dart` editor; `payment_account_repository.dart`.

- [ ] After create (or after first movement), opening is read-only. Corrections = adjustment movement, not rewrite.
- [ ] Changelog. Commit.

### Task 1.5: N11 `resync_session` hijack (High, cloud)

**Files:** `supabase/functions/activate/index.ts` `handleResyncSession`.

- [x] Do not stamp `shop_id` from `device_id` alone. Require the calling user already owns that license (or a signed device token / existing `shop_id` match). Reject anonymous callers who only know the public App Reference ID.
- [ ] Deploy activate function. Changelog. Commit.

### Task 1.6: N10 Staff must not create the first owner PIN

**Files:** `lib/features/staff/staff_ui.dart` `promptOwnerPinForSwitch`; Daily Gate owner continue.

- [ ] If `hasPin()` is false and current role is staff, refuse switch-to-owner (message: owner must set PIN first). Creating the first PIN is owner-only (Settings while already owner).
- [ ] `verifyStaffPin` empty → true stays for first-run owner devices, not for staff escalation.
- [ ] Changelog. Commit.

---

## Wave 2 — publish week (data integrity, backup, sync heal)

### Task 2.1: N1 Backup is actually all business tables

**Files:** `lib/features/backup/backup_service.dart`; `test/backup_test.dart`; ARB `backupExportHint` / `backupImportConfirmBody`.

- [ ] Export/import every shop-scoped business table (orders, customers, staff, permissions, cash sessions, suppliers, POs, payment accounts, AP, equity, shop profile, recurring expenses). Delete those tables on restore. Clear `stock_lots` on restore (rebuild from movements).
- [ ] Copy must not say “all data” until the list matches. Changelog. Commit.

### Task 2.2: P14 + N2 + N3 Wipe / promote / force-apply parity

**Files:** `lib/data/local/database.dart` `wipeSyncedData`; `lib/data/local/shop_data_transition_service.dart` `promoteShopIdentity`; `supabase/functions/sync_force_apply/index.ts` `ALLOWED_TABLES`.

- [ ] Wipe `staffPermissions`. Promote `staff_permissions`. Allowlist `staff_permissions` + `shop_profiles`.
- [ ] If shipping 0075: wipe `cashTopUps`, promote `cash_top_ups`, allowlist `cash_top_ups`. Otherwise leave top-ups out of the store build.
- [ ] Deploy `sync_force_apply`. Changelog. Commit.

### Task 2.3: P5 Inventory value from FIFO lots

**Files:** `lib/features/analytics/analytics_providers.dart` `stockValueProvider`.

- [ ] Σ(`stock_lots.remainingQty × unitCost`) for tracked products; qty × `costPrice` only if lots empty.
- [ ] Grep Balance Sheet inventory readers. Test costPrice edit does not restatement lots. Changelog. Commit.

### Task 2.4: P18 + P21 Confirmations

**Files:** `lib/features/invoices/invoice_detail_screen.dart`; `lib/features/orders/order_detail_sheet.dart` `_markReturn`.

- [ ] Invoice refund dialog includes formatted kyat (same pattern as `orderReturnConfirmBody`).
- [ ] Unconverted order cancel: `showDialog` before `setStatus('cancelled')`.
- [ ] i18n. Changelog. Commit.

---

## Wave 3 — storefront (only if the public shop is live)

Skip this wave if storefront is off for v1 publish.

### Task 3.1: N4 Proof object must exist

**Files:** `supabase/functions/storefront/index.ts`.

- [ ] After prefix check, Storage `download`/`list` the object; 400 if missing.
- [ ] Deploy storefront function. Changelog. Commit.

### Task 3.2: N5 Return charged prices to the client

**Files:** `supabase/functions/storefront/index.ts` `submit_order` response; `lib/storefront/storefront_page.dart` confirmation PNG.

- [ ] Response includes server line prices + total. Confirmation uses those, not the first catalog fetch.
- [ ] Changelog. Commit.

### Task 3.3: N6 + N7 Cap under concurrency and duplicate lines

**Files:** `supabase/functions/storefront/index.ts` `sumOrderedByProduct` + insert.

- [ ] Aggregate qty by `product_id` before compare. Insert order+items in one transaction (or advisory lock per shop+product) so two concurrent submits cannot both pass the same remaining.
- [ ] Deploy. Changelog. Commit.

### Task 3.4: N8 + N9 Cap release + phone normalize

**Files:** `storefront/index.ts`; `lib/features/storefront/storefront_repository.dart`.

- [ ] Cap sum excludes `delivered` (or subtracts fulfilled). Normalize phones (`09` / `9` / `+959`) before blocklist match.
- [ ] Deploy. Changelog. Commit.

---

## Wave 4 — later (correct but narrower)

Do after Waves 0–2. Each is one commit.

| ID | What | Files |
|----|------|--------|
| P9 | Allow negative credit outstanding (customer credit) or issue a credit-note row | `credit_repository.dart` |
| P10 | `closeSession` refuse if `closedAt` already set | `cash_session_repository.dart` |
| P11 | Tombstone/exclude `stock_levels` for deleted products | `inventory_repository.dart`, `stockValueProvider` |
| P12 | `recordPayment` throw if amount > outstanding | `accounts_payable_repository.dart` |
| P13 | Top products use post-order-discount allocation | `analytics_calculator.dart` |
| P15 | Recurring generateDueExpenses copy template `accountId` | `recurring_expense_repository.dart` |
| N12 | Daily gate: treat empty `shopId` as “still needed” or block shell until license `shopId` applied | `operating_mode_providers.dart`, `app.dart` |
| N13 | Daily gate fail-closed with retry, not skip (keep spinner-death fix: retry, don’t return false) | `operating_mode_providers.dart` |
| N14 | One-shot hash remaining plaintext `staff_members.pin` on app start / promote | `staff_repository.dart` |

---

## Explicitly not in this plan

- Negative stock on sale (UI already caps; tests allow repo negative).
- Year-end close (documented device-local).
- Equity drawings vs till (deliberate; top-ups are the till path).
- Two-device `INV-yyyyMMdd-NNN` (0074 quarantine).
- Share subject `Invoice …` English, township English, storage spam, trial fail-open.

---

## Suggested git cadence

One commit per task above (wave 0 = 5 commits, etc.). Changelog entry per commit in `PROJECT_SPEC.md` §12. After Wave 0: `flutter analyze` + `flutter test`. After Wave 1.5–1.6 and 2.2 / 3.x: deploy the matching Edge Function (`deploy` skill).

## Device verify after Wave 0 (cannot skip)

- Type discount 10000 digit-by-digit — display is 10,000 not 1.
- Credit sale, paid-now 4000 cash — Confirm shows 4000; till expected +4000.
- Convert unpaid COD — invoice not fully paid; till unchanged.
- Print credit receipt — ကျန်ငွေ line present.
- Refund an old invoice-only sale after enabling track stock — qty unchanged.
