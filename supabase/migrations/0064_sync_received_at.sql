-- Server-authoritative change-feed cursor for sync (audit finding H2).
--
-- Problem: the pull cursor was a high-water mark over `updated_at`, but
-- `updated_at` is CLIENT-generated (each device's own wall clock). A device
-- whose clock runs behind creates rows stamped BELOW every other device's
-- already-advanced cursor — those rows are then NEVER pulled by anyone, a
-- permanent silent loss. LWW merge decisions were equally skewed.
--
-- Fix: every synced table gains `received_at timestamptz`, stamped by the
-- SERVER (`clock_timestamp()`) via trigger on every INSERT and UPDATE —
-- inserts (device pushes, storefront orders, service-role force-apply) and
-- updates (tombstones, mutable-row edits) alike. The pull cursor now rides
-- this monotonic-ish, skew-free column, so no event can fall permanently
-- below a watermark due to device clock skew. Residual race (transactions
-- committing out of stamp order) is closed client-side by re-fetching with
-- a small overlap window — re-applying a row is idempotent (every mapper's
-- LWW guard no-ops on equal-or-older `updated_at`).
--
-- One-time cost: existing rows get the migration moment as `received_at`,
-- so every device's first pull after this migration re-fetches its shop's
-- full history once (fresh `sync.rcursor.*` keys). Safe — just slower.
--
-- `updated_at` itself is deliberately left client-generated: replacing it
-- with a server stamp would mix timestamp domains in the client-side LWW
-- merge (local unsynced edits carry device time) and needs a hybrid-clock
-- design — out of scope here. Concurrent same-row edits still resolve by
-- device clock; the catastrophic "row never syncs at all" class is what
-- this migration eliminates.

create function touch_received_at() returns trigger as $$
begin
  new.received_at := clock_timestamp();
  return new;
end $$ language plpgsql;

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
    execute format('alter table %I add column if not exists received_at timestamptz not null default clock_timestamp();', t);
    execute format('drop trigger if exists trg_%s_received_at on %I;', t, t);
    execute format('create trigger trg_%s_received_at before insert or update on %I for each row execute function touch_received_at();', t, t);
    execute format('create index if not exists idx_%s_shop_received on %I (shop_id, received_at);', t, t);
  end loop;
end $$;
