-- Realtime "Online" sync tier — an admin-granted premium flag (no automated
-- billing gateway exists yet, same precedent as the multi-device fee: a shop
-- pays and support/admin flips this on) that lets a device push updates to
-- other devices under the shop within seconds instead of the default 5-minute
-- poll. The base offline-first behavior is completely unchanged either way —
-- this only shortens how quickly a PULL happens when the device is online.

alter table licenses add column if not exists realtime_enabled boolean not null default false;

-- Publish the tables where "another device sees it almost immediately"
-- actually matters day-to-day: sales, cached stock levels, and the order
-- Kanban board. RLS still applies to realtime the same as normal reads, so
-- this doesn't loosen shop_isolation — a device only ever receives change
-- events for rows it could already select.
--
-- `alter publication ... add table` errors if the table is already a member
-- (unlike most DDL here, there's no "if not exists" form), so guard each one
-- against pg_publication_tables to keep this migration safely re-runnable.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'sales'
  ) then
    alter publication supabase_realtime add table sales;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'stock_levels'
  ) then
    alter publication supabase_realtime add table stock_levels;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table orders;
  end if;
end $$;
