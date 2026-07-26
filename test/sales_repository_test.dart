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
}
