-- Stock-level duplicate race (client audit 2026-08-25) — one row per
-- (shop_id, product_id), enforced by the database.
--
-- The client can legitimately create a stock_levels row from a foreign
-- stock_movements delta BEFORE the originating device's canonical
-- stock_levels push lands (the movement is enqueued before the level row,
-- and a failed-then-healed level push widens the window arbitrarily). That
-- phantom insert uses a random local id; when the canonical row later
-- arrives it carries a DIFFERENT primary key, and nothing stopped both from
-- existing — remotely or locally. Every client read keyed on product
-- (`getSingleOrNull`) then throws, crashing checkout / restock / refunds /
-- order conversion on that device, and movement deltas are silently skipped.
--
-- Fix mirrors local Drift schema v33: dedupe historical duplicates (keep
-- the earliest created_at as canonical), then enforce uniqueness. A second
-- row now fails loudly into the sync engine's quarantine instead of
-- silently corrupting every device that pulls it.

-- Keep the earliest row per (shop_id, product_id); hard-delete the rest.
-- Hard-delete (not soft): a tombstone would fan out and delete the
-- canonical row on every other device.
with ranked as (
  select id,
         row_number() over (
           partition by shop_id, product_id
           order by created_at asc, id asc
         ) as rn
  from stock_levels
)
delete from stock_levels
where id in (select id from ranked where rn > 1);

create unique index if not exists stock_levels_shop_product_uniq
  on stock_levels (shop_id, product_id);
