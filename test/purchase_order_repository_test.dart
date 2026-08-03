import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/features/purchasing/purchase_order_repository.dart';

void main() {
  late AppDatabase db;
  late InventoryRepository inventory;
  late PurchaseOrderRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    inventory = InventoryRepository(db, 'shop-1');
    repo = PurchaseOrderRepository(db, 'shop-1', inventory);
  });

  tearDown(() async => db.close());

  test('savePO computes itemsTotal from the lines and enqueues outbox',
      () async {
    final productId =
        await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 5);

    final id = await repo.savePO(
      supplierName: 'Acme Distribution',
      lines: [
        PurchaseOrderDraftLine(
            productId: productId, name: 'Coke', qty: 10, unitCost: 500),
      ],
    );

    final po = await repo.getOrder(id);
    expect(po, isNotNull);
    expect(po!.itemsTotal, 5000);
    expect(po.status, 'open');
    expect(po.poNo, startsWith('PO-'));

    final outbox = await db.select(db.outbox).get();
    expect(outbox.any((o) => o.entityTable == 'purchase_orders'), isTrue);
    expect(outbox.any((o) => o.entityTable == 'purchase_order_items'), isTrue);
  });

  test('receivePO increases stock and records a purchase movement per line',
      () async {
    final productId =
        await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 5);
    final poId = await repo.savePO(
      supplierName: 'Acme',
      lines: [
        PurchaseOrderDraftLine(
            productId: productId, name: 'Coke', qty: 10, unitCost: 500),
      ],
    );

    await repo.receivePO(poId);

    final products = await inventory.watchProducts().first;
    final coke = products.firstWhere((p) => p.product.id == productId);
    expect(coke.quantity, 15); // 5 + 10

    final movements = await db.select(db.stockMovements).get();
    expect(
        movements.any((m) =>
            m.productId == productId &&
            m.type == 'purchase' &&
            m.qtyDelta == 10 &&
            m.unitCost == 500),
        isTrue);

    final po = await repo.getOrder(poId);
    expect(po!.status, 'received');
    expect(po.receivedAt, isNotNull);
  });

  test('receivePO is idempotent — a second call does not double-add stock',
      () async {
    final productId =
        await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 0);
    final poId = await repo.savePO(
      supplierName: 'Acme',
      lines: [
        PurchaseOrderDraftLine(
            productId: productId, name: 'Coke', qty: 10, unitCost: 500),
      ],
    );

    await repo.receivePO(poId);
    await repo.receivePO(poId);

    final products = await inventory.watchProducts().first;
    final coke = products.firstWhere((p) => p.product.id == productId);
    expect(coke.quantity, 10); // not 20
  });

  test('cancelPO never touches stock', () async {
    final productId =
        await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 5);
    final poId = await repo.savePO(
      supplierName: 'Acme',
      lines: [
        PurchaseOrderDraftLine(
            productId: productId, name: 'Coke', qty: 10, unitCost: 500),
      ],
    );

    await repo.cancelPO(poId);

    final products = await inventory.watchProducts().first;
    final coke = products.firstWhere((p) => p.product.id == productId);
    expect(coke.quantity, 5); // unchanged
    final po = await repo.getOrder(poId);
    expect(po!.status, 'cancelled');
  });

  test('receivePO on a cancelled PO is a no-op (guard is status != open, '
      'not just != received)', () async {
    final productId =
        await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 5);
    final poId = await repo.savePO(
      supplierName: 'Acme',
      lines: [
        PurchaseOrderDraftLine(
            productId: productId, name: 'Coke', qty: 10, unitCost: 500),
      ],
    );

    await repo.cancelPO(poId);
    await repo.receivePO(poId);

    final products = await inventory.watchProducts().first;
    final coke = products.firstWhere((p) => p.product.id == productId);
    expect(coke.quantity, 5); // unchanged — never un-cancels via receivePO
    final po = await repo.getOrder(poId);
    expect(po!.status, 'cancelled');
  });

  test('watchOrders excludes other shops', () async {
    final productId =
        await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 5);
    await repo.savePO(
      supplierName: 'Acme',
      lines: [
        PurchaseOrderDraftLine(
            productId: productId, name: 'Coke', qty: 1, unitCost: 500),
      ],
    );
    final otherInventory = InventoryRepository(db, 'shop-2');
    final otherRepo = PurchaseOrderRepository(db, 'shop-2', otherInventory);
    final otherProductId = await otherInventory.upsertProduct(
        name: 'Other', salePrice: 100, quantity: 1);
    await otherRepo.savePO(
      supplierName: 'Other Co',
      lines: [
        PurchaseOrderDraftLine(
            productId: otherProductId, name: 'Other', qty: 1, unitCost: 50),
      ],
    );

    final rows = await repo.watchOrders().first;
    expect(rows, hasLength(1));
    expect(rows.single.supplierName, 'Acme');
  });
}
