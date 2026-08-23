import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/data/repositories/sales_repository.dart';
import 'package:mm_pos/data/repositories/stock_lots.dart';
import 'package:mm_pos/features/orders/orders_repository.dart';

/// Regression coverage for audit QA-C1: order conversions must carry the
/// same FIFO accounting as Sell-screen checkouts, and refunds must never
/// re-enter returned units into stock at cost 0.
void main() {
  late AppDatabase db;
  late InventoryRepository inv;
  late OrdersRepository orders;
  late SalesRepository sales;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    inv = InventoryRepository(db, 'shop-1');
    orders = OrdersRepository(db, 'shop-1');
    sales = SalesRepository(db, 'shop-1');
  });
  tearDown(() async => db.close());

  Future<String> seedProduct() => inv.upsertProduct(
        name: 'Shirt',
        salePrice: 10000,
        costPrice: 6000,
        quantity: 5,
      );

  Future<String> convertDeliveredOrder(String productId) async {
    final orderId = await orders.saveOrder(
      customerName: 'U Ba',
      channel: 'facebook',
      lines: [
        OrderDraftLine(
            productId: productId, name: 'Shirt', price: 10000, qty: 2),
      ],
    );
    await orders.handOffToCarrier(orderId, carrier: 'in_city');
    return orders.convertToSale(orderId);
  }

  test('convertToSale consumes FIFO lots and stamps the real costSnapshot',
      () async {
    final productId = await seedProduct();
    final saleId = await convertDeliveredOrder(productId);

    final items = await sales.saleItems(saleId);
    expect(items.single.costSnapshot, 12000,
        reason: '2 units x 6000 lot cost — Analytics profit depends on this');

    final level = await (db.select(db.stockLevels)
          ..where((s) => s.productId.equals(productId)))
        .getSingle();
    expect(level.quantity, 3);

    final move = await (db.select(db.stockMovements)
          ..where((m) => m.refId.equals(saleId) & m.type.equals('sale')))
        .getSingle();
    expect(move.unitCost, 6000);
  });

  test(
      'refunding a converted order restores the returned units at their '
      'original lot cost — never cost 0', () async {
    final productId = await seedProduct();
    final saleId = await convertDeliveredOrder(productId);

    await sales.refundSale(saleId);

    // Whatever way the lots are derived from here on, every unit must be
    // valued at its true 6000 cost: consuming everything must cost
    // 5 * 6000, not a kyat less.
    final cost = await consumeStockLots(db,
        productId: productId, qty: 5, fallbackUnitCost: 6000);
    expect(cost, 30000,
        reason: 'a 0-cost lot here means profit is overstated by the '
            'returned units\' full real cost');
  });

  test(
      'legacy rows written without costSnapshot heal at the product\'s '
      'cost price on refund, not at 0', () async {
    final productId = await seedProduct();
    final now = DateTime.now();

    // Hand-write what OLD versions of OrdersRepository.convertToSale
    // produced: a sale item with no costSnapshot whose stock-out movement
    // consumed no lot.
    const saleId = 'legacy-order-sale';
    await db.into(db.sales).insert(SalesCompanion.insert(
          id: saleId,
          shopId: 'shop-1',
          invoiceNo: 'INV-20260823-001',
          subtotal: const Value(20000),
          total: const Value(20000),
          paid: const Value(20000),
          finalizedAt: Value(now),
          updatedAt: Value(now),
        ));
    await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
          id: 'legacy-item',
          shopId: 'shop-1',
          saleId: saleId,
          productId: productId,
          nameSnapshot: 'Shirt',
          priceSnapshot: 10000,
          qty: 2,
          lineTotal: 20000,
          updatedAt: Value(now),
        ));
    await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
          id: 'legacy-move',
          shopId: 'shop-1',
          productId: productId,
          type: 'sale',
          qtyDelta: -2,
          refId: const Value(saleId),
          updatedAt: Value(now),
        ));

    await sales.refundSale(saleId);

    final returnMove = await (db.select(db.stockMovements)
          ..where((m) => m.type.equals('return')))
        .getSingle();
    expect(returnMove.unitCost, 6000,
        reason: 'return movement must stamp the fallback cost, not 0');

    final cost = await consumeStockLots(db,
        productId: productId, qty: 5, fallbackUnitCost: 6000);
    expect(cost, 30000);
  });

  test('free-text lines (empty productId) never mint ghost stock lots',
      () async {
    final productId = await seedProduct();
    final orderId = await orders.saveOrder(
      customerName: 'U Ba',
      channel: 'facebook',
      lines: [
        OrderDraftLine(
            productId: null, name: 'Fried rice', price: 2000, qty: 2),
        OrderDraftLine(
            productId: productId, name: 'Shirt', price: 10000, qty: 1),
      ],
    );
    await orders.handOffToCarrier(orderId, carrier: 'in_city');
    final saleId = await orders.convertToSale(orderId);

    await sales.refundSale(saleId);

    final ghostLots = await (db.select(db.stockLots)
          ..where((l) => l.productId.equals('')))
        .get();
    expect(ghostLots, isEmpty,
        reason: 'refund of a free-text line must not open a lot for ""');
  });

  test('QA-H1: double convert is idempotent — one sale, one deduction',
      () async {
    final productId = await seedProduct();
    final orderId = await orders.saveOrder(
      customerName: 'U Ba',
      channel: 'facebook',
      lines: [
        OrderDraftLine(
            productId: productId, name: 'Shirt', price: 10000, qty: 2),
      ],
    );
    await orders.handOffToCarrier(orderId, carrier: 'in_city');

    // Both conversions race past the outside check before either commits.
    final ids = await Future.wait([
      orders.convertToSale(orderId),
      orders.convertToSale(orderId),
    ]);

    expect(ids.first, ids[1],
        reason: 'the loser must return the winner\'s sale id, not mint '
            'a second append-only sale');
    expect(await db.select(db.sales).get(), hasLength(1));

    final soldUnits = await (db.select(db.stockMovements)
          ..where((m) => m.type.equals('sale') & m.refId.isNotNull()))
        .get();
    expect(soldUnits.fold<int>(0, (s, m) => s + m.qtyDelta), -2,
        reason: 'stock deducted exactly once for the order\'s qty');
  });
}
