import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/data/repositories/sales_repository.dart';
import 'package:mm_pos/features/credit/credit_repository.dart';
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

  test('invoice numbering uses max-seq scan: gaps and refund rows never '
      'collide or inflate the sequence (audit M3)', () async {
    final now = DateTime.now();
    final prefix = 'INV-'
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-';

    // Seed today's ledger with a gap (001 and 003 exist — e.g. a pulled row
    // from another device) plus a refund credit-note (RFD prefix).
    Future<void> seedSale(String invoiceNo) async {
      await db.into(db.sales).insert(SalesCompanion.insert(
            id: invoiceNo, // unique enough for the test
            shopId: 'shop-1',
            invoiceNo: invoiceNo,
            subtotal: const Value(100),
            total: const Value(100),
            finalizedAt: Value(now),
            updatedAt: Value(now),
          ));
    }

    await seedSale('${prefix}001');
    await seedSale('${prefix}003');
    await seedSale('RFD-${prefix.substring(4)}001');

    // Counting rows (3) would mint 004 — colliding with nothing but wrong;
    // the old count also broke when refunds shared the day. Max-scan mints
    // the true next number after the highest seen sequence.
    final result = await sales.finalizeSale(
      cart: CartState(lines: [
        CartLine(product: await seedProduct(name: 'X', price: 10, qty: 5), qty: 1)
      ]),
      paymentMethod: 'cash',
      paid: 10,
    );
    expect(result.invoiceNo, '${prefix}004');

    // And the next one continues the sequence.
    final second = await sales.finalizeSale(
      cart: CartState(lines: [
        CartLine(product: await seedProduct(name: 'Y', price: 10, qty: 5), qty: 1)
      ]),
      paymentMethod: 'cash',
      paid: 10,
    );
    expect(second.invoiceNo, '${prefix}005');
  });

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

  test('a split sale where entries do not sum to the total is rejected',
      () async {
    // The checkout UI's own split-payment dialog already refuses to enable
    // Save until the rows sum to exactly the total — this proves the
    // repository doesn't just trust that boundary silently (2026-08-27
    // accounting review, Medium finding).
    final coke = await seedProduct(name: 'Coke', price: 700, qty: 10);
    expect(
      () => sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: coke, qty: 1)]),
        payments: const [PaymentEntry('cash', 300), PaymentEntry('kbzpay', 300)],
      ),
      throwsArgumentError,
    );
    // Nothing was written for the rejected attempt.
    expect(await db.select(db.sales).get(), isEmpty);
  });

  test('a split sale whose entries sum to the total finalizes normally',
      () async {
    final coke = await seedProduct(name: 'Coke', price: 700, qty: 10);
    final result = await sales.finalizeSale(
      cart: CartState(lines: [CartLine(product: coke, qty: 1)]),
      payments: const [PaymentEntry('cash', 300), PaymentEntry('kbzpay', 400)],
    );
    final sale = await (db.select(db.sales)
          ..where((s) => s.id.equals(result.saleId)))
        .getSingle();
    expect(sale.paid, 700);
    expect(sale.paymentMethod, 'split');
    expect(await db.select(db.payments).get(), hasLength(2));
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

    test('refunding a partially-repaid credit sale closes nothing — the '
        'debt was already settled (audit H-2)', () async {
      final p = await seedProduct(name: 'Rice bag', price: 10000, qty: 5);
      final sold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 1)]),
        paymentMethod: 'credit',
        paid: 4000,
        customerName: 'Ma Ma',
      );
      // The customer settles the remaining 6000 through the credit book.
      await CreditRepository(db, 'shop-1')
          .recordRepayment(customerName: 'Ma Ma', amount: 6000);

      await sales.refundSale(sold.saleId);

      // No phantom closure row on top of the real repayment — the old raw
      // `total - paid` math minted +6000 again, wiping the customer's
      // other real debts via FIFO spillover.
      final repayments = await (db.select(db.creditPayments)
            ..where((c) => c.customerName.equals('Ma Ma')))
          .get();
      expect(
        repayments
            .where((r) => (r.note ?? '').startsWith('Refund closure')),
        isEmpty,
      );
    });

    test('refund closure covers only this invoice when repayments spread '
        'across invoices, and is method=credit (audit H-2)', () async {
      final rice = await seedProduct(name: 'Rice', price: 5000, qty: 10);
      final oil = await seedProduct(name: 'Oil', price: 8000, qty: 10);
      // Older invoice (5,000 owed), then newer invoice (8,000 owed).
      final older = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: rice, qty: 1)]),
        paymentMethod: 'credit',
        paid: 0,
        customerName: 'Ko Ko',
      );
      final newer = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: oil, qty: 1)]),
        paymentMethod: 'credit',
        paid: 0,
        customerName: 'Ko Ko',
      );
      // Pool of 9,000 allocated oldest-first: clears `older`, leaves 4,000
      // still owed on `newer`.
      await CreditRepository(db, 'shop-1')
          .recordRepayment(customerName: 'Ko Ko', amount: 9000);

      await sales.refundSale(older.saleId);
      var koKoPayments = await (db.select(db.creditPayments)
            ..where((c) => c.customerName.equals('Ko Ko')))
          .get();
      var closures = koKoPayments
          .where((r) => (r.note ?? '').startsWith('Refund closure'))
          .toList();
      expect(closures, isEmpty); // older was already fully repaid

      await sales.refundSale(newer.saleId);
      koKoPayments = await (db.select(db.creditPayments)
            ..where((c) => c.customerName.equals('Ko Ko')))
          .get();
      closures = koKoPayments
          .where((r) => (r.note ?? '').startsWith('Refund closure'))
          .toList();
      expect(closures.single.amount, 4000); // only the still-unpaid part
      expect(closures.single.method, 'credit'); // never drawer cash
    });

    test('a second reversal row for the same sale is rejected by the '
        'sales_refund_once unique index (audit H-1 cross-device backstop)',
        () async {
      final p = await seedProduct(name: 'Soap', price: 800, qty: 20);
      final sold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 1)]),
        paymentMethod: 'cash',
        paid: 800,
      );
      await sales.refundSale(sold.saleId);

      // Simulates another device's refund row arriving via sync pull while
      // this device's own refund already exists locally.
      final now = DateTime.now();
      await expectLater(
        db.into(db.sales).insert(SalesCompanion.insert(
              id: 'other-device-refund',
              shopId: 'shop-1',
              invoiceNo: 'INV-dup',
              total: const Value(-800),
              paid: const Value(-800),
              refundOfSaleId: Value(sold.saleId),
              finalizedAt: Value(now),
              updatedAt: Value(now),
            )),
        throwsA(anything),
      );
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
            'credit_payments',
          }));
      // stock_levels is deliberately ABSENT: its quantity is a counter
      // reconciled from the stock_movements ledger on every device — it
      // must never be pushed as an absolute LWW value (audit finding H1).
      expect(tables, isNot(contains('stock_levels')));
    });
  });

  group('split payment', () {
    test('finalizeSale writes one Payments row per entry and stamps the '
        "sale's paymentMethod as 'split'", () async {
      final p = await seedProduct(name: 'Rice bag', price: 5000, qty: 5);
      final sold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 1)]),
        payments: const [
          PaymentEntry('cash', 3000),
          PaymentEntry('kbzpay', 2000),
        ],
      );

      final row = await sales.getSale(sold.saleId);
      expect(row.paymentMethod, 'split');
      expect(row.paid, 5000);
      expect(row.total, 5000);
      expect(row.changeDue, 0);

      final pays = await (db.select(db.payments)
            ..where((pay) => pay.saleId.equals(sold.saleId)))
          .get();
      expect(pays, hasLength(2));
      expect(
        pays.map((p) => (p.method, p.amount)).toSet(),
        {('cash', 3000), ('kbzpay', 2000)},
      );
    });

    test('refunding a split sale mirrors EACH original method by its own '
        'amount — not one lump row, not all-cash (owner-picked proportional '
        'refund policy)', () async {
      final p = await seedProduct(name: 'Rice bag', price: 5000, qty: 5);
      final sold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 1)]),
        payments: const [
          PaymentEntry('cash', 3000),
          PaymentEntry('kbzpay', 2000),
        ],
      );

      final refund = await sales.refundSale(sold.saleId);

      final refundRow = await sales.getSale(refund.saleId);
      expect(refundRow.paymentMethod, 'split');
      expect(refundRow.paid, -5000);

      final refundPays = await (db.select(db.payments)
            ..where((pay) => pay.saleId.equals(refund.saleId)))
          .get();
      expect(refundPays, hasLength(2));
      expect(
        refundPays.map((p) => (p.method, p.amount)).toSet(),
        {('cash', -3000), ('kbzpay', -2000)},
      );
    });

    test('refunding a plain cash sale with change given reverses only the '
        'settled amount, not the raw tendered amount (pre-existing '
        'over-refund fixed as part of the proportional-mirror rewrite)',
        () async {
      final p = await seedProduct(name: 'Soap', price: 800, qty: 20);
      // Tender 1,000 for an 800 total — 200 change handed back at sale time,
      // so only 800 was ever actually kept (the single Payments row is
      // written as `settled`, not the raw `paid`).
      final sold = await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: p, qty: 1)]),
        paymentMethod: 'cash',
        paid: 1000,
      );
      final original = await sales.getSale(sold.saleId);
      expect(original.paid, 1000); // raw tendered, includes the change
      final originalPays = await (db.select(db.payments)
            ..where((pay) => pay.saleId.equals(sold.saleId)))
          .get();
      expect(originalPays.single.amount, 800); // settled, excludes change

      final refund = await sales.refundSale(sold.saleId);
      final refundPays = await (db.select(db.payments)
            ..where((pay) => pay.saleId.equals(refund.saleId)))
          .get();
      // Must reverse the 800 actually kept, not the 1000 raw tendered —
      // the customer only ever net-paid 800, and the 200 change is already
      // out of the till from the moment it was handed back at sale time.
      expect(refundPays.single.amount, -800);
    });

    test('finalizeSale requires paymentMethod+paid unless payments is given',
        () async {
      final p = await seedProduct(name: 'Soap', price: 800, qty: 20);
      expect(
        () => sales.finalizeSale(
          cart: CartState(lines: [CartLine(product: p, qty: 1)]),
        ),
        throwsArgumentError,
      );
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
