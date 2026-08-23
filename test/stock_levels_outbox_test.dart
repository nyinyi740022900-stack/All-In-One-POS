import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';

/// Regression tests for audit finding H1: `stock_levels.quantity` is a
/// counter and must never be pushed as an absolute LWW value. Quantity
/// changes ride the append-only `stock_movements` ledger only; the
/// stock_levels row itself is pushed just once at creation, and again only
/// when the owner actually changes the reorder level (a real per-shop
/// setting, safe under LWW).
void main() {
  late AppDatabase db;
  late InventoryRepository inventory;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    inventory = InventoryRepository(db, 'shop-1');
  });

  tearDown(() async => db.close());

  Future<List<OutboxData>> pendingRows() => db.select(db.outbox).get();
  Future<void> drainOutbox() => db.delete(db.outbox).go();

  test('creating a product with stock still pushes the stock_levels row once',
      () async {
    final id =
        await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 10);
    final rows = await pendingRows();
    expect(rows.where((o) => o.entityTable == 'stock_levels'), hasLength(1));
    expect(rows.where((o) => o.entityTable == 'stock_movements'), hasLength(1));
    expect(rows.where((o) => o.entityTable == 'products'), hasLength(1));
    // Sanity: the creation push carries the opening quantity snapshot.
    final levelRow = await (db.select(db.stockLevels)
          ..where((s) => s.productId.equals(id)))
        .getSingle();
    expect(levelRow.quantity, 10);
  });

  test('selling / adjusting quantity does NOT enqueue stock_levels',
      () async {
    final id =
        await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 10);
    await drainOutbox();

    await inventory.adjustStock(
        productId: id, delta: 5, type: 'purchase', unitCost: 500);

    var rows = await pendingRows();
    expect(rows.where((o) => o.entityTable == 'stock_levels'), isEmpty,
        reason: 'quantity churn must never become an absolute-LWW push');
    expect(rows.where((o) => o.entityTable == 'stock_movements'), hasLength(1));

    await drainOutbox();
    // A pure reorder-level edit IS pushed (real setting, safe under LWW).
    await inventory.upsertProduct(
        id: id,
        name: 'Coke',
        salePrice: 700,
        quantity: 15,
        reorderLevel: 5);
    rows = await pendingRows();
    expect(rows.where((o) => o.entityTable == 'stock_levels'), hasLength(1),
        reason: 'reorder-level changes are settings and must sync');

    await drainOutbox();
    // Same quantity movement again (no reorder change) — nothing pushed.
    await inventory.upsertProduct(
        id: id,
        name: 'Coke',
        salePrice: 700,
        quantity: 20,
        reorderLevel: 5);
    rows = await pendingRows();
    expect(rows.where((o) => o.entityTable == 'stock_levels'), isEmpty);
  });
}
