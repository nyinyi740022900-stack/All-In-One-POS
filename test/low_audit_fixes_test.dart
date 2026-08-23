import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/input/thousands_formatter.dart';
import 'package:mm_pos/core/money.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/data/repositories/sales_repository.dart';
import 'package:mm_pos/features/orders/orders_repository.dart';

/// Regression coverage for the audit's code-fixed Low tier:
/// - QA-L1 restoring a cancelled converted order detaches the refunded sale
///   so it can convert again
/// - QA-L3 absurd digit runs clamp to maxMoneyInputKyat instead of silently
///   reading as 0
/// (QA-L2/L6 are dialog/validation wiring covered by manual smoke; QA-L4/L5
/// are documented limitations — see PROJECT_SPEC #236.)

void main() {
  group('QA-L3: money input clamps instead of collapsing to zero', () {
    test('parseThousands clamps an overlong digit run', () {
      expect(parseThousands('9' * 25), maxMoneyInputKyat,
          reason: 'int.tryParse returns null past 19 digits — the old '
              'fallback turned a huge paste into 0 Ks');
      expect(parseThousands('12,000'), 12000);
      expect(parseThousands(''), 0);
      expect(parseThousands('abc'), 0);
    });

    test('Money.fromString preserves sign while clamping magnitude', () {
      expect(Money.fromString('9' * 25).kyat, maxMoneyInputKyat);
      expect(Money.fromString('-${'9' * 25}').kyat, -maxMoneyInputKyat);
      expect(Money.fromString('1,500').kyat, 1500);
    });
  });

  group('QA-L1: restoreOrder on a cancelled converted order', () {
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

    test('detaches the refunded sale, resets payment status, and the order '
        'can convert again', () async {
      final productId = await inv.upsertProduct(
          name: 'Shirt', salePrice: 10000, costPrice: 6000, quantity: 5);
      final orderId = await orders.saveOrder(
        customerName: 'U Ba',
        channel: 'facebook',
        lines: [
          OrderDraftLine(
              productId: productId, name: 'Shirt', price: 10000, qty: 1),
        ],
      );
      await orders.handOffToCarrier(orderId, carrier: 'in_city');
      final saleId = await orders.convertToSale(orderId);

      // Cancel with conversion = refund + status flip (detail sheet flow).
      await sales.refundSale(saleId);
      await orders.setStatus(orderId, 'cancelled');

      await orders.restoreOrder(orderId);

      final restored = await orders.getOrder(orderId);
      expect(restored.status, 'new');
      expect(restored.saleId, isNull,
          reason: 'stale link blocked convert forever (dead-end state)');
      expect(restored.paymentStatus, 'unpaid');

      // And the pipeline accepts it again — a fresh sale, not the old one.
      final secondSale = await orders.convertToSale(orderId);
      expect(secondSale, isNot(saleId));
      final allSales = await db.select(db.sales).get();
      expect(allSales.map((s) => s.id), containsAll([saleId, secondSale]),
          reason: 'append-only ledger keeps BOTH the refunded pair and the '
              'fresh re-sale');
    });
  });
}
