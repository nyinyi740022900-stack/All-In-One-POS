-- Delivery address, carried over when an Order converts to a Sale. Was
-- previously dropped entirely on conversion, so a converted order's
-- invoice/receipt had nowhere to deliver it printed on. Existing
-- shop_isolation policy on sales already covers this column.

alter table sales add column if not exists delivery_address text;
