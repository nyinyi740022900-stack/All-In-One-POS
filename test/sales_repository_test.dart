import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/data/repositories/sales_repository.dart';
import 'package:mm_pos/features/sell/cart.dart';

void main() {
  late AppDatabase db;
  late InventoryRepository inventory;
  late SalesRepository sales;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    inventory = InventoryRepository(db, 'shop-1');
    sales = SalesRepository(db, 'shop-1');
  });

  tearDown(() async => db.close());

  Future<Product> seedProduct(
      {required String name,
      required int price,
      required int qty,
      int? wholesalePrice}) async {
    final id = await inventory.upsertProduct(
        name: name,
        salePrice: price,
        wholesalePrice: wholesalePrice,
        quantity: qty);
    return (await inventory.watchProducts().first)
        .firstWhere((p) => p.product.id == id)
        .product;
  }

  test('finalizeSale writes sale, items, payment and decrements stock',
      () async {
    final coke = await seedProduct(name: 'Coke', price: 700, qty: 10);
    final cart = CartState(lines: [CartLine(product: coke, qty: 3)]);

    final result = await sales.finalizeSale(
      cart: cart,
      paymentMethod: 'cash',
      paid: 5000,
    );

    // Sale row.
    final sale = await (db.select(db.sales)
          ..where((s) => s.id.equals(result.saleId)))
        .getSingle();
    expect(sale.total, 2100);
    expect(sale.paid, 5000);
    expect(sale.changeDue, 2900);
    expect(sale.invoiceNo, startsWith('INV-'));

    // One sale item, one payment.
    expect(await db.select(db.saleItems).get(), hasLength(1));
    expect(await db.select(db.payments).get(), hasLength(1));

    // Stock decremented 10 -> 7.
    final stock = await (db.select(db.stockLevels)
          ..where((s) => s.productId.equals(coke.id)))
        .getSingle();
    expect(stock.quantity, 7);

    // A 'sale' stock movement was recorded (alongside the opening movement).
    final saleMoves = (await db.select(db.stockMovements).get())
        .where((m) => m.type == 'sale')
        .toList();
    expect(saleMoves.single.qtyDelta, -3);
  });

  test('finalizeSale records which device rang the sale up', () async {
    final coke = await seedProduct(name: 'Coke', price: 700, qty: 10);
    final result = await sales.finalizeSale(
      cart: CartState(lines: [CartLine(product: coke, qty: 1)]),
      paymentMethod: 'cash',
      paid: 700,
      deviceId: 'device-abc',
    );
    final sale = await (db.select(db.sales)
          ..where((s) => s.id.equals(result.saleId)))
        .getSingle();
    expect(sale.deviceId, 'device-abc');
  });

  test('finalizeSale leaves deviceId null when not provided', () async {
    final coke = await seedProduct(name: 'Coke', price: 700, qty: 10);
    final result = await sales.finalizeSale(
      cart: CartState(lines: [CartLine(product: coke, qty: 1)]),
      paymentMethod: 'cash',
      paid: 700,
    );
    final sale = await (db.select(db.sales)
          ..where((s) => s.id.equals(result.saleId)))
        .getSingle();
    expect(sale.deviceId, isNull);
  });

  test('trackStock:false skips stock movement + decrement (invoice only)',
      () async {
    final p = await seedProduct(name: 'Service', price: 5000, qty: 10);
    await sales.finalizeSale(
      cart: CartState(lines: [CartLine(product: p, qty: 2)]),
      paymentMethod: 'cash',
      paid: 10000,
      trackStock: false,
    );

    // No 'sale' stock movement recorded, stock level untouched (the opening
    // movement from seeding still exists).
    final saleMoves = (await db.select(db.stockMovements).get())
        .where((m) => m.type == 'sale');
    expect(saleMoves, isEmpty);
    final stock = await (db.select(db.stockLevels)
          ..where((s) => s.productId.equals(p.id)))
        .getSingle();
    expect(stock.quantity, 10); // unchanged

    // The sale + payment still happened.
    expect(await db.select(db.sales).get(), hasLength(1));
    expect(await db.select(db.payments).get(), hasLength(1));
  });

  test('finalizeSale stamps the staffId that rang up the sale', () async {
    final p = await seedProduct(name: 'Gum', price: 500, qty: 5);
    final result = await sales.finalizeSale(
      cart: CartState(lines: [CartLine(product: p, qty: 1)]),
      paymentMethod: 'cash',
      paid: 500,
      staffId: 'staff-123',
    );
    final sale = await (db.select(db.sales)
          ..where((s) => s.id.equals(result.saleId)))
        .getSingle();
    expect(sale.staffId, 'staff-123');
  });

  test('discount is applied to the total', () async {
    final p = await seedProduct(name: 'Water', price: 400, qty: 5);
    final cart = CartState(
      lines: [CartLine(product: p, qty: 2)],
      discount: 100,
    );
    final r = await sales.finalizeSale(
        cart: cart, paymentMethod: 'kbzpay', paid: 700);
    final sale =
        await (db.select(db.sales)..where((s) => s.id.equals(r.saleId)))
            .getSingle();
    expect(sale.subtotal, 800);
    expect(sale.discount, 100);
    expect(sale.total, 700);
  });

  test('finalizeSale prices at the cart\'s customerTier, not salePrice',
      () async {
    final p = await seedProduct(
        name: 'Rice bag', price: 1000, wholesalePrice: 800, qty: 20);
    final cart = CartState(
      lines: [CartLine(product: p, qty: 3)],
      customerTier: 'wholesale',
    );
    final r = await sales.finalizeSale(
        cart: cart, paymentMethod: 'cash', paid: 2400);

    final sale =
        await (db.select(db.sales)..where((s) => s.id.equals(r.saleId)))
            .getSingle();
    expect(sale.subtotal, 2400); // 3 x 800, not 3 x 1000

    final item = await (db.select(db.saleItems)
          ..where((i) => i.saleId.equals(r.saleId)))
        .getSingle();
    expect(item.priceSnapshot, 800);
    expect(item.lineTotal, 2400);
  });

  test('invoice numbers increment within the same day', () async {
    final p = await seedProduct(name: 'Soap', price: 800, qty: 20);
    final a = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 1)]),
        paymentMethod: 'cash',
        paid: 800);
    final b = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 1)]),
        paymentMethod: 'cash',
        paid: 800);
    expect(a.invoiceNo, endsWith('-001'));
    expect(b.invoiceNo, endsWith('-002'));
  });

  test('empty cart cannot be finalized', () async {
    expect(
      () => sales.finalizeSale(
          cart: const CartState(), paymentMethod: 'cash', paid: 0),
      throwsStateError,
    );
  });

  test('outbox queues sale, items, payment and stock rows for sync', () async {
    final p = await seedProduct(name: 'Match', price: 100, qty: 50);
    await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 2)]),
        paymentMethod: 'cash',
        paid: 200);
    final tables =
        (await db.select(db.outbox).get()).map((o) => o.entityTable).toSet();
    expect(
        tables,
        containsAll(<String>{
          'sales',
          'sale_items',
          'payments',
          'stock_movements',
          'stock_levels',
        }));
  });

  group('refundSale', () {
    test('creates a negated reversal sale and restores stock', () async {
      final p = await seedProduct(name: 'Coke', price: 700, qty: 10);
      final sold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 3)]),
        paymentMethod: 'cash',
        paid: 2100,
      );

      final refund = await sales.refundSale(sold.saleId);

      expect(refund.invoiceNo, startsWith('RFD-'));
      final refundRow = await (db.select(db.sales)
            ..where((s) => s.id.equals(refund.saleId)))
          .getSingle();
      expect(refundRow.total, -2100);
      expect(refundRow.subtotal, -2100);
      expect(refundRow.paid, -2100);
      expect(refundRow.refundOfSaleId, sold.saleId);

      final refundItems = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(refund.saleId)))
          .get();
      expect(refundItems.single.qty, -3);
      expect(refundItems.single.lineTotal, -2100);

      // Stock restored 7 -> 10.
      final stock = await (db.select(db.stockLevels)
            ..where((s) => s.productId.equals(p.id)))
          .getSingle();
      expect(stock.quantity, 10);

      final returnMoves = (await db.select(db.stockMovements).get())
          .where((m) => m.type == 'return')
          .toList();
      expect(returnMoves.single.qtyDelta, 3);

      final refundPayments = await (db.select(db.payments)
            ..where((pay) => pay.saleId.equals(refund.saleId)))
          .get();
      expect(refundPayments.single.amount, -2100);
    });

    test('the original sale row is never mutated', () async {
      final p = await seedProduct(name: 'Water', price: 400, qty: 5);
      final sold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 2)]),
        paymentMethod: 'cash',
        paid: 800,
      );
      await sales.refundSale(sold.saleId);

      final original = await (db.select(db.sales)
            ..where((s) => s.id.equals(sold.saleId)))
          .getSingle();
      expect(original.total, 800);
      expect(original.paid, 800);
    });

    test('refunding twice throws StateError', () async {
      final p = await seedProduct(name: 'Soap', price: 800, qty: 20);
      final sold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 1)]),
        paymentMethod: 'cash',
        paid: 800,
      );
      await sales.refundSale(sold.saleId);
      expect(() => sales.refundSale(sold.saleId), throwsStateError);
    });

    test('refunding an unpaid credit sale inserts a closing credit payment',
        () async {
      final p = await seedProduct(name: 'Rice bag', price: 50000, qty: 10);
      final sold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 1)]),
        paymentMethod: 'credit',
        paid: 0,
        customerName: 'Ma Ma',
      );
      await sales.refundSale(sold.saleId);

      final repayments = await (db.select(db.creditPayments)
            ..where((c) => c.customerName.equals('Ma Ma')))
          .get();
      expect(repayments.single.amount, 50000);

      // No payment row inserted (nothing was actually paid to reverse).
      final refund = await sales.refundOf(sold.saleId);
      final refundPayments = await (db.select(db.payments)
            ..where((pay) => pay.saleId.equals(refund!.id)))
          .get();
      expect(refundPayments, isEmpty);
    });

    test('outbox queues rows for every affected table', () async {
      final p = await seedProduct(name: 'Match', price: 100, qty: 50);
      final sold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 2)]),
        paymentMethod: 'credit',
        paid: 0,
        customerName: 'Ko Ko',
      );
      await db.delete(db.outbox).go(); // clear the finalizeSale entries
      await sales.refundSale(sold.saleId);

      final tables =
          (await db.select(db.outbox).get()).map((o) => o.entityTable).toSet();
      expect(
          tables,
          containsAll(<String>{
            'sales',
            'sale_items',
            'stock_movements',
            'stock_levels',
            'credit_payments',
          }));
    });
  });

  group('FIFO cost basis', () {
    test('a sale consumes lots oldest-first and snapshots the exact total',
        () async {
      final id = await inventory.upsertProduct(
          name: 'Rice', salePrice: 2000, costPrice: 1000, quantity: 0);
      // Two restocks at different costs — FIFO should drain the first
      // before touching the second.
      await inventory.adjustStock(
          productId: id, delta: 5, type: 'purchase', unitCost: 800);
      await inventory.adjustStock(
          productId: id, delta: 10, type: 'purchase', unitCost: 1200);
      final product =
          (await inventory.watchProducts().first).firstWhere((p) => p.product.id == id).product;

      final cart = CartState(lines: [CartLine(product: product, qty: 8)]);
      final result =
          await sales.finalizeSale(cart: cart, paymentMethod: 'cash', paid: 16000);

      final item = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(result.saleId)))
          .getSingle();
      // 5 units @ 800 (first lot, fully drained) + 3 units @ 1200 (spills
      // into the second lot) — not 8 * the product's flat cost_price (1000).
      expect(item.costSnapshot, 5 * 800 + 3 * 1200);

      // Second lot has 7 left (10 - 3); first lot is gone.
      final lots = await (db.select(db.stockLots)
            ..where((t) => t.productId.equals(id)))
          .get();
      expect(lots.single.remainingQty, 7);
      expect(lots.single.unitCost, 1200);
    });

    test('oversell beyond tracked lots falls back to the flat cost price',
        () async {
      final id = await inventory.upsertProduct(
          name: 'Sugar', salePrice: 1500, costPrice: 900, quantity: 0);
      await inventory.adjustStock(
          productId: id, delta: 2, type: 'purchase', unitCost: 700);
      final product =
          (await inventory.watchProducts().first).firstWhere((p) => p.product.id == id).product;

      // Sell 5 with only 2 tracked — 3 units fall back to costPrice (900).
      final cart = CartState(lines: [CartLine(product: product, qty: 5)]);
      final result =
          await sales.finalizeSale(cart: cart, paymentMethod: 'cash', paid: 7500);

      final item = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(result.saleId)))
          .getSingle();
      expect(item.costSnapshot, 2 * 700 + 3 * 900);
    });

    test('a product with no restock at all costs entirely at the flat price',
        () async {
      final id = await inventory.upsertProduct(
          name: 'Legacy item', salePrice: 1000, costPrice: 600, quantity: 20);
      // seeded via the opening-balance path (quantity on create), not an
      // explicit restock — still pushes an opening lot at costPrice, so
      // this should price straight from that lot, matching costPrice.
      final product =
          (await inventory.watchProducts().first).firstWhere((p) => p.product.id == id).product;

      final cart = CartState(lines: [CartLine(product: product, qty: 4)]);
      final result =
          await sales.finalizeSale(cart: cart, paymentMethod: 'cash', paid: 4000);

      final item = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(result.saleId)))
          .getSingle();
      expect(item.costSnapshot, 4 * 600);
    });

    test('refunding restores a lot at the original cost, not today\'s price',
        () async {
      final id = await inventory.upsertProduct(
          name: 'Oil', salePrice: 3000, costPrice: 1500, quantity: 0);
      await inventory.adjustStock(
          productId: id, delta: 5, type: 'purchase', unitCost: 1500);
      var product =
          (await inventory.watchProducts().first).firstWhere((p) => p.product.id == id).product;

      final sold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: product, qty: 5)]),
        paymentMethod: 'cash',
        paid: 15000,
      );
      // All 5 units sold — no lots left.
      expect(
          await (db.select(db.stockLots)..where((t) => t.productId.equals(id)))
              .get(),
          isEmpty);

      await sales.refundSale(sold.saleId);
      // Refund restored a lot at the original 1500 cost, even though the
      // product's flat cost price later changes below.
      final restoredLots = await (db.select(db.stockLots)
            ..where((t) => t.productId.equals(id)))
          .get();
      expect(restoredLots.single.remainingQty, 5);
      expect(restoredLots.single.unitCost, 1500);

      // Bump the product's flat cost price to prove the next sale still
      // prices off the restored lot (1500), not the new flat price (5000).
      await inventory.upsertProduct(
          id: id, name: 'Oil', salePrice: 3000, costPrice: 5000);
      product = (await inventory.watchProducts().first)
          .firstWhere((p) => p.product.id == id)
          .product;

      final resold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: product, qty: 5)]),
        paymentMethod: 'cash',
        paid: 15000,
      );
      final item = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(resold.saleId)))
          .getSingle();
      expect(item.costSnapshot, 5 * 1500);
    });
  });
}
