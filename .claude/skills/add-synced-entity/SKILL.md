---
name: add-synced-entity
description: Add a new offline-synced Drift + Supabase table to All In One POS (e.g. orders, order_items, customers). Use when adding ANY entity that must persist locally and sync to the cloud. Encodes the full checklist so no step (especially RLS) is missed.
---

# Add a synced entity

Adding a table that syncs is spread across ~6 files. Missing any one silently
breaks sync or (worse) security. Do ALL of these, in order.

## 1. Drift table — `lib/data/local/tables.dart`
```dart
class Orders extends Table with SyncColumns {   // SyncColumns = id, shopId, createdAt, updatedAt, isDeleted, dirty
  TextColumn get customerName => text().nullable()();
  // ... columns ...
  @override
  Set<Column> get primaryKey => {id};
}
```

## 2. Register + migrate — `lib/data/local/database.dart`
- Add the table to `@DriftDatabase(tables: [...])`.
- Bump `schemaVersion`.
- Add an `onUpgrade` branch: `if (from < N) await m.createTable(orders);`
  (or `m.addColumn(...)` for a new column).

## 3. Regenerate
```bash
dart run build_runner build
```

## 4. Sync mapper — `lib/data/sync/sync_mappers.dart`
Add a `SyncTableDef` (snake_case `toRemote` + last-write-wins `upsertLocal`,
mirroring `_products`) and register it in the `syncTables` list. **Counters
(like stock) must sync as append-only movement deltas, not absolute values.**

## 5. Supabase migration — `supabase/migrations/00NN_<name>.sql`
Create the table **with shop isolation RLS** — never dev-open:
```sql
create table if not exists orders ( id text primary key, shop_id text not null, ... );
create index if not exists idx_orders_shop_updated on orders (shop_id, updated_at);
alter table orders enable row level security;
drop policy if exists shop_isolation on orders;
create policy shop_isolation on orders
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
```
⚠️ Every synced table MUST have `shop_isolation`. (See the 0012 lesson in
CLAUDE.md — dropping/forgetting it makes the table default-deny and breaks the
app or, if dev-open, leaks every shop's data.)

## 6. Repository + providers
Write mutations that (a) write the Drift row in a transaction and (b) enqueue
to the `outbox` (`entityTable`, `rowId`, `op`, `payload`). Mirror an existing
repository (e.g. `SalesRepository`, `CreditRepository`).

## 7. Verify + deploy
- `flutter analyze` && `flutter test` (add a repo/aggregate test).
- Apply the migration via the `deploy` skill; test a same-shop insert + a
  cross-shop reject (RLS) before considering it done.
- Update `PROJECT_SPEC.md` §12 changelog.
