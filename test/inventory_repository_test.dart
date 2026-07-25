import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';

void main() {
  late AppDatabase db;
  late InventoryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = InventoryRepository(db, 'shop-1');
  });

  tearDown(() async => db.close());

  test('upsertProduct persists product + stock and enqueues outbox', () async {
    final id = await repo.upsertProduct(
      name: 'Coca-Cola',
      salePrice: 700,
      costPrice: 550,
      quantity: 24,
      reorderLevel: 6,
    );

    final products = await repo.watchProducts().first;
    expect(products, hasLength(1));
    expect(products.single.product.id, id);
    expect(products.single.product.name, 'Coca-Cola');
    expect(products.single.quantity, 24);
    expect(products.single.isLowStock, isFalse);

    // Outbox should have queued product + stock upserts for sync.
    final outbox = await db.select(db.outbox).get();
    final tables = outbox.map((o) => o.entityTable).toSet();
    expect(tables, containsAll(<String>{'products', 'stock_levels'}));
    expect(outbox.every((o) => o.op == 'upsert'), isTrue);
  });

  test('stock changes are recorded as ledger movements (opening/adjustment)',
      () async {
    final id = await repo.upsertProduct(
        name: 'Coke', salePrice: 700, quantity: 24, reorderLevel: 6);
    // Create writes an 'opening' movement for the full quantity.
    var moves = await (db.select(db.stockMovements)
          ..where((m) => m.productId.equals(id)))
        .get();
    expect(moves, hasLength(1));
    expect(moves.single.type, 'opening');
    expect(moves.single.qtyDelta, 24);

    // Editing the quantity records an 'adjustment' for the delta.
    await repo.upsertProduct(
        id: id, name: 'Coke', salePrice: 700, quantity: 20, reorderLevel: 6);
    moves = await (db.select(db.stockMovements)
          ..where((m) => m.productId.equals(id)))
        .get();
    expect(moves, hasLength(2));
    final adj = moves.firstWhere((m) => m.type == 'adjustment');
    expect(adj.qtyDelta, -4); // 24 -> 20

    // No movement when the quantity is unchanged.
    await repo.upsertProduct(
        id: id, name: 'Coke', salePrice: 700, quantity: 20, reorderLevel: 6);
    moves = await (db.select(db.stockMovements)
          ..where((m) => m.productId.equals(id)))
        .get();
    expect(moves, hasLength(2)); // unchanged
  });

  test('low stock is flagged when quantity <= reorder level', () async {
    await repo.upsertProduct(
        name: 'Match box', quantity: 5, reorderLevel: 10);
    final p = (await repo.watchProducts().first).single;
    expect(p.isLowStock, isTrue);
  });

  test('deleteProduct tombstones and hides the product', () async {
    final id = await repo.upsertProduct(name: 'Soap', quantity: 3);
    await repo.deleteProduct(id);
    final products = await repo.watchProducts().first;
    expect(products, isEmpty);

    final delete = await (db.select(db.outbox)
          ..where((o) => o.op.equals('delete')))
        .get();
    expect(delete, hasLength(1));
    expect(delete.single.rowId, id);
  });

  test('shop scoping isolates products by shop', () async {
    await repo.upsertProduct(name: 'A', quantity: 1);
    final otherShop = InventoryRepository(db, 'shop-2');
    expect(await otherShop.watchProducts().first, isEmpty);
    expect(await repo.watchProducts().first, hasLength(1));
  });

  test('upsertCategory persists and enqueues outbox', () async {
    final id = await repo.upsertCategory(name: 'Drinks');
    final cats = await repo.watchCategories().first;
    expect(cats.single.id, id);
    expect(cats.single.name, 'Drinks');

    final outbox = await db.select(db.outbox).get();
    expect(outbox.any((o) => o.entityTable == 'categories'), isTrue);
  });

  test('deleteCategory tombstones and hides it', () async {
    final id = await repo.upsertCategory(name: 'Snacks');
    await repo.deleteCategory(id);
    expect(await repo.watchCategories().first, isEmpty);

    final del = await (db.select(db.outbox)..where((o) => o.op.equals('delete')))
        .get();
    expect(del.any((o) => o.entityTable == 'categories' && o.rowId == id),
        isTrue);
  });

  test('product keeps its assigned category id', () async {
    final catId = await repo.upsertCategory(name: 'Drinks');
    await repo.upsertProduct(name: 'Coke', categoryId: catId, quantity: 1);
    final p = (await repo.watchProducts().first).single;
    expect(p.product.categoryId, catId);
  });

  group('adjustStock', () {
    test('a restock increases the cached level and records a purchase move',
        () async {
      final id = await repo.upsertProduct(name: 'Rice', quantity: 10);
      await repo.adjustStock(
          productId: id, delta: 25, type: 'purchase', note: 'from supplier');

      final p = (await repo.watchProducts().first).single;
      expect(p.quantity, 35);

      final move = (await repo.watchStockMovements(id).first).firstWhere(
          (m) => m.type == 'purchase');
      expect(move.qtyDelta, 25);
      expect(move.note, 'from supplier');
    });

    test('a negative adjustment decreases the cached level', () async {
      final id = await repo.upsertProduct(name: 'Soap', quantity: 20);
      await repo.adjustStock(
          productId: id, delta: -3, type: 'adjustment', note: 'Damaged');

      final p = (await repo.watchProducts().first).single;
      expect(p.quantity, 17);

      final move = (await repo.watchStockMovements(id).first)
          .firstWhere((m) => m.type == 'adjustment');
      expect(move.qtyDelta, -3);
    });

    test('zero delta is rejected', () async {
      final id = await repo.upsertProduct(name: 'Water', quantity: 5);
      expect(
        () => repo.adjustStock(productId: id, delta: 0, type: 'adjustment'),
        throwsArgumentError,
      );
    });

    test('watchStockMovements is newest-first and enqueues outbox rows',
        () async {
      final id = await repo.upsertProduct(name: 'Match', quantity: 5);
      await repo.adjustStock(productId: id, delta: 10, type: 'purchase');
      await repo.adjustStock(productId: id, delta: -2, type: 'adjustment');

      final moves = await repo.watchStockMovements(id).first;
      // Newest first: adjustment(-2), purchase(+10), opening(+5).
      expect(moves.map((m) => m.type).toList(),
          ['adjustment', 'purchase', 'opening']);

      final tables = (await db.select(db.outbox).get())
          .map((o) => o.entityTable)
          .toSet();
      expect(tables, containsAll(<String>{'stock_movements', 'stock_levels'}));
    });
  });
}
