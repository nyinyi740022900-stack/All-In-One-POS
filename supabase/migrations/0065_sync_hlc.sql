-- Hybrid Logical Clock column for deterministic conflict resolution
-- (audit H2 residual). Clients mint `hlc` at push time and compare it as a
-- total-ordered tuple when merging pulled rows, so concurrent offline edits
-- converge on one winner on every device regardless of device wall-clock
-- skew. Nullable everywhere: rows written by pre-upgrade clients (and by
-- the storefront / service role) carry NULL and get a deterministic
-- received_at-derived stand-in during merge. No index needed — hlc is only
-- read row-by-row with the data, never filtered.

do $$
declare t text;
begin
  foreach t in array array[
    'categories','products','stock_levels','stock_movements',
    'sales','sale_items','payments','license_payments','credit_payments',
    'orders','order_items','staff_members','customers','expenses',
    'cash_sessions','device_labels','recurring_expenses','suppliers',
    'purchase_orders','purchase_order_items','payment_accounts',
    'supplier_payments','equity_entries','shop_profiles'
  ]
  loop
    execute format('alter table %I add column if not exists hlc text;', t);
  end loop;
end $$;
