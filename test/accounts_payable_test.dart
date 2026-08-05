import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/suppliers/accounts_payable.dart';

void main() {
  group('aggregateAccountsPayable (pure)', () {
    PurchaseOrder receivedPo(String supplier, int total) => PurchaseOrder(
          id: 'po-$supplier-$total',
          shopId: 'shop-1',
          poNo: 'PO-1',
          supplierName: supplier,
          status: 'received',
          itemsTotal: total,
          receivedAt: DateTime(2026, 7, 1),
          createdAt: DateTime(2026, 7, 1),
          updatedAt: DateTime(2026, 7, 1),
          isDeleted: false,
          dirty: false,
        );

    SupplierPayment pay(String supplier, int amount) => SupplierPayment(
          id: 'pay-$supplier-$amount',
          shopId: 'shop-1',
          supplierName: supplier,
          method: 'cash',
          amount: amount,
          createdAt: DateTime(2026, 7, 2),
          updatedAt: DateTime(2026, 7, 2),
          isDeleted: false,
          dirty: false,
        );

    test('outstanding = billed (received POs) - payments', () {
      final result = aggregateAccountsPayable(
        [receivedPo('Golden Trading', 100000)],
        [pay('Golden Trading', 30000)],
      );
      expect(result, hasLength(1));
      expect(result.single.name, 'Golden Trading');
      expect(result.single.outstanding, 70000);
    });

    test('fully-paid suppliers are dropped by default', () {
      final result = aggregateAccountsPayable(
        [receivedPo('Aung Supplies', 5000)],
        [pay('Aung Supplies', 5000)],
      );
      expect(result, isEmpty);
    });

    test('includeSettled: true keeps fully-paid suppliers, at 0 owed', () {
      final result = aggregateAccountsPayable(
        [receivedPo('Aung Supplies', 5000)],
        [pay('Aung Supplies', 5000)],
        includeSettled: true,
      );
      expect(result, hasLength(1));
      expect(result.single.outstanding, 0);
    });

    test('multiple received POs from the same supplier accumulate', () {
      final result = aggregateAccountsPayable(
        [receivedPo('Golden Trading', 100000), receivedPo('Golden Trading', 50000)],
        const [],
      );
      expect(result.single.billed, 150000);
    });

    test('different suppliers are kept separate', () {
      final result = aggregateAccountsPayable(
        [receivedPo('A', 10000), receivedPo('B', 20000)],
        const [],
      );
      expect(result, hasLength(2));
    });
  });
}
