-- Audit H-1 fix — make "a sale can only be refunded once" a DB invariant.
--
-- Until now the single-refund rule lived only in app code
-- (`SalesRepository.refundSale` checked `refundOf(saleId)` BEFORE opening
-- its transaction, and 0024's index on refund_of_sale_id was non-unique).
-- Two devices refunding the same sale offline both pushed a reversal row;
-- each new 'return' stock movement and negative payment applied once per
-- device — double stock restore, double cash reversal, silently.
--
-- Fix: dedupe any historical duplicate refunds (keep the earliest — it is
-- the canonical reversal), then enforce uniqueness with a partial unique
-- index. A second device's push now FAILS loudly into the sync engine's
-- quarantine instead of silently applying. Mirrors local Drift schema v32.

-- Keep the earliest refund per (shop_id, refund_of_sale_id); soft-delete the
-- rest so analytics/reports net exactly one reversal per refunded sale.
with dupes as (
  select id,
         row_number() over (
           partition by shop_id, refund_of_sale_id
           order by finalized_at asc, created_at asc, id asc
         ) as rn
  from sales
  where refund_of_sale_id is not null
)
update sales s
set is_deleted = true,
    updated_at = now()
from dupes d
where s.id = d.id
  and d.rn > 1;

create unique index if not exists sales_refund_once
  on sales (shop_id, refund_of_sale_id)
  where refund_of_sale_id is not null;
