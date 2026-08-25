-- Renewal receipt: give a shop that submitted a payment request something it
-- can quote and come back to, instead of the bare request UUID the /renew
-- page shows today.
--
-- Also lays the groundwork for the MyanMyanPay gateway (see PROJECT_SPEC §12)
-- so that work needs no second migration: `invoice_no` is what we will send
-- as MMPay's `orderId`, so the number the shop quotes on Viber, the row in
-- this table, and the order in MMPay's own dashboard all reconcile on ONE
-- number. `payment_status` is deliberately separate from `status`: one
-- tracks the money, the other the licence, and the webhook can advance the
-- first while the second is still pending (payment taken, minting failed) —
-- a state the shop must be able to see rather than sit in the dark about.

-- Human-quotable id. Derived from the row's own (already unique) id rather
-- than a sequence or a timestamp: no extra table, and two requests submitted
-- in the same millisecond cannot collide — the same reasoning as
-- submit_order's `order_no` (storefront/index.ts).
alter table license_requests
  add column if not exists invoice_no      text,
  add column if not exists payment_status  text not null default 'manual',
                                        -- manual | awaiting | paid | failed | expired
  add column if not exists mmpay_order_id  text,
  add column if not exists mmpay_expires_at timestamptz,
  add column if not exists paid_at         timestamptz;

-- Backfill with the same rule new rows use, so an old request opened through
-- a receipt link is not the one row without a number.
update license_requests
   set invoice_no = 'INV-' || upper(substring(replace(id, '-', '') from 1 for 8))
 where invoice_no is null;

create unique index if not exists license_requests_invoice_no_key
  on license_requests (invoice_no) where invoice_no is not null;

-- Reconciliation: money in, licence never minted. Without this index the
-- admin console has no way to find these, and they look identical to an
-- ordinary pending request.
create index if not exists license_requests_paid_unfulfilled_idx
  on license_requests (created_at desc)
  where payment_status = 'paid' and status = 'pending';

-- NOTE: no select policy is added here on purpose. license_requests stays
-- service-role only (0010) — the receipt is served by the `storefront` Edge
-- Function, which holds the service role and returns a hand-picked subset of
-- columns. Opening this table to anon would expose every shop's payment
-- proof path and phone number to anyone who can guess a row.
