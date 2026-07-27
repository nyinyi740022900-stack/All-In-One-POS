-- FIFO cost basis: sale_items gains cost_snapshot, the total cost of goods
-- sold for that line (mirrors line_total — a total, not a per-unit price
-- like price_snapshot), FIFO-consumed from the device's local purchase lots
-- at sale time. Null on rows written before this feature (Analytics falls
-- back to the product's flat cost_price for those).
--
-- The FIFO lot ledger itself (StockLots) is intentionally local-only and has
-- no remote table — each device derives it from the already-synced
-- stock_movements ledger, so there is nothing to add here for it.

alter table sale_items add column if not exists cost_snapshot integer;

-- Existing shop_isolation policy on sale_items already covers this column.
