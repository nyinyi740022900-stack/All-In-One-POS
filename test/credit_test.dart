import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/data/repositories/sales_repository.dart';
import 'package:mm_pos/features/credit/credit_repository.dart';
import 'package:mm_pos/features/sell/cart.dart';

void main() {
  group('CreditRepository.aggregate (pure)', () {
    Sale creditSale(String name, int total, int paid) => Sale(
          id: 'sale-$name-$total-$paid',
          shopId: 'shop-1',
          invoiceNo: 'INV-1',
          subtotal: total,
          discount: 0,
          total: total,
          paid: paid,
          changeDue: 0,
          paymentMethod: 'credit',
          customerName: name,
          finalizedAt: DateTime(2026, 7, 1),
          createdAt: DateTime(2026, 7, 1),
          updatedAt: DateTime(2026, 7, 1),
          isDeleted: false,
          dirty: false,
        );

    CreditPayment repay(String name, int amount) => CreditPayment(
          id: 'pay-$name-$amount',
          shopId: 'shop-1',
          customerName: name,
          method: 'cash',
          amount: amount,
          createdAt: DateTime(2026, 7, 2),
          updatedAt: DateTime(2026, 7, 2),
          isDeleted: false,
          dirty: false,
        );

    test('outstanding = billed - down-payment - repayments', () {
      final result = CreditRepository.aggregate(
        [creditSale('Aung', 10000, 2000)],
        [repay('Aung', 3000)],
      );
      expect(result, hasLength(1));
      expect(result.single.name, 'Aung');
      expect(result.single.outstanding, 5000); // 10000 - 2000 - 3000
      expect(result.single.openInvoices, 1);
    });

    test('fully-settled customers are dropped', () {
      final result = CreditRepository.aggregate(
        [creditSale('Bo', 5000, 0)],
        [repay('Bo', 5000)],
      );
      expect(result, isEmpty);
    });

    test('includeSettled: true keeps fully-settled customers, at 0 owed', () {
      final result = CreditRepository.aggregate(
        [creditSale('Bo', 5000, 0)],
        [repay('Bo', 5000)],
        includeSettled: true,
      );
      expect(result, hasLength(1));
      expect(result.single.name, 'Bo');
      expect(result.single.outstanding, 0);
    });

    test('includeSettled: true still excludes an unnamed credit sale', () {
      final result = CreditRepository.aggregate(
        [creditSale('', 5000, 0)],
        const [],
        includeSettled: true,
      );
      expect(result, isEmpty);
    });

    test('multiple invoices for one customer sum up', () {
      final result = CreditRepository.aggregate(
        [creditSale('Cho', 3000, 0), creditSale('Cho', 2000, 500)],
        const [],
      );
      expect(result.single.outstanding, 4500); // 3000 + 1500
      expect(result.single.openInvoices, 2);
    });

    test('customers sorted by outstanding, largest first', () {
      final result = CreditRepository.aggregate(
        [creditSale('Small', 1000, 0), creditSale('Big', 9000, 0)],
        const [],
      );
      expect(result.map((c) => c.name).toList(), ['Big', 'Small']);
    });

    test('unnamed credit sales are ignored', () {
      final result = CreditRepository.aggregate(
        [creditSale('', 5000, 0)],
        const [],
      );
      expect(result, isEmpty);
    });

    Sale dated(String id, String name, int total, DateTime at) => Sale(
          id: id,
          shopId: 'shop-1',
          invoiceNo: id,
          subtotal: total,
          discount: 0,
          total: total,
          paid: 0,
          changeDue: 0,
          paymentMethod: 'credit',
          customerName: name,
          finalizedAt: at,
          createdAt: at,
          updatedAt: at,
          isDeleted: false,
          dirty: false,
        );

    test('owedBySale allocates repayments oldest-invoice first', () {
      final s1 = dated('s1', 'Aung', 3000, DateTime(2026, 7, 1));
      final s2 = dated('s2', 'Aung', 2000, DateTime(2026, 7, 2));
      final owed = CreditRepository.owedBySale(
        [s2, s1], // deliberately out of order
        [repay('Aung', 4000)],
      );
      expect(owed['s1'], 0); // oldest fully covered (3000)
      expect(owed['s2'], 1000); // remaining 1000 applied → 2000-1000
    });

    test('owedBySale: full repayment clears every invoice', () {
      final s1 = dated('s1', 'Bo', 3000, DateTime(2026, 7, 1));
      final s2 = dated('s2', 'Bo', 2000, DateTime(2026, 7, 2));
      final owed =
          CreditRepository.owedBySale([s1, s2], [repay('Bo', 5000)]);
      expect(owed['s1'], 0);
      expect(owed['s2'], 0);
    });

    Sale creditSaleWithId(String customerId, String name, int total, int paid) =>
        Sale(
          id: 'sale-$customerId-$total-$paid',
          shopId: 'shop-1',
          invoiceNo: 'INV-1',
          subtotal: total,
          discount: 0,
          total: total,
          paid: paid,
          changeDue: 0,
          paymentMethod: 'credit',
          customerName: name,
          customerId: customerId,
          finalizedAt: DateTime(2026, 7, 1),
          createdAt: DateTime(2026, 7, 1),
          updatedAt: DateTime(2026, 7, 1),
          isDeleted: false,
          dirty: false,
        );

    test('two sales with the same customerId group together even if the '
        'typed name changed (e.g. a directory rename)', () {
      final result = CreditRepository.aggregate(
        [
          creditSaleWithId('cust-1', 'Daw Mya', 3000, 0),
          creditSaleWithId('cust-1', 'Daw Mya (renamed)', 2000, 0),
        ],
        const [],
      );
      expect(result, hasLength(1));
      expect(result.single.outstanding, 5000);
      expect(result.single.customerId, 'cust-1');
    });

    test('a repayment linked by customerId settles a sale under a '
        'differently-typed name for the same customer', () {
      final sale = creditSaleWithId('cust-2', 'Ko Ko', 5000, 0);
      final payment = CreditPayment(
        id: 'pay-1',
        shopId: 'shop-1',
        customerName: 'Ko Ko Naing', // typo/variant of the same person
        customerId: 'cust-2',
        method: 'cash',
        amount: 5000,
        createdAt: DateTime(2026, 7, 2),
        updatedAt: DateTime(2026, 7, 2),
        isDeleted: false,
        dirty: false,
      );
      final result = CreditRepository.aggregate([sale], [payment]);
      expect(result, isEmpty); // fully settled despite the name mismatch
    });

    test('two sales with the SAME typed name but no customerId still group '
        'by name (legacy behavior preserved)', () {
      final result = CreditRepository.aggregate(
        [creditSale('Legacy Customer', 1000, 0),
         creditSale('Legacy Customer', 2000, 0)],
        const [],
      );
      expect(result, hasLength(1));
      expect(result.single.outstanding, 3000);
      expect(result.single.customerId, isNull);
    });
  });

  group('CreditRepository with DB', () {
    late AppDatabase db;
    late CreditRepository credit;
    late SalesRepository sales;
    late InventoryRepository inventory;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      credit = CreditRepository(db, 'shop-1');
      sales = SalesRepository(db, 'shop-1');
      inventory = InventoryRepository(db, 'shop-1');
    });

    tearDown(() async => db.close());

    test('a credit sale records partial paid and shows as outstanding',
        () async {
      final id = await inventory.upsertProduct(
          name: 'Rice bag', salePrice: 10000, quantity: 5);
      final product = (await inventory.watchProducts().first)
          .firstWhere((p) => p.product.id == id)
          .product;

      await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: product, qty: 1)]),
        paymentMethod: 'credit',
        paid: 4000,
        customerName: 'Daw Mya',
      );

      final sale = await sales.watchSales().first;
      expect(sale.single.paymentMethod, 'credit');
      expect(sale.single.paid, 4000);
      // Payment tender recorded is the actual down-payment, not the total.
      final payment = (await db.select(db.payments).get()).single;
      expect(payment.amount, 4000);

      final customers = CreditRepository.aggregate(
        await credit.watchCreditSales().first,
        await credit.watchRepayments().first,
      );
      expect(customers.single.name, 'Daw Mya');
      expect(customers.single.outstanding, 6000);
    });

    test('a partial CASH sale (not the credit method) counts as credit',
        () async {
      final id = await inventory.upsertProduct(
          name: 'Big bag', salePrice: 10000, quantity: 5);
      final product = (await inventory.watchProducts().first)
          .firstWhere((p) => p.product.id == id)
          .product;

      await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: product, qty: 1)]),
        paymentMethod: 'cash', // NOT 'credit'
        paid: 4000, // partial
        customerName: 'U Ba',
        customerPhone: '09123',
      );

      final customers = CreditRepository.aggregate(
        await credit.watchCreditSales().first,
        await credit.watchRepayments().first,
      );
      expect(customers.single.name, 'U Ba');
      expect(customers.single.outstanding, 6000);
      expect(customers.single.phone, '09123');
    });

    Future<void> seedCreditSale(String name, int total, int paid) async {
      final id = await inventory.upsertProduct(
          name: 'Item for $name', salePrice: total, quantity: 5);
      final product = (await inventory.watchProducts().first)
          .firstWhere((p) => p.product.id == id)
          .product;
      await sales.finalizeSale(
        cart: CartState(lines: [CartLine(product: product, qty: 1)]),
        paymentMethod: 'credit',
        paid: paid,
        customerName: name,
      );
    }

    test('recordRepayment writes row + enqueues outbox', () async {
      await seedCreditSale('Daw Mya', 10000, 4000); // outstanding 6000
      await credit.recordRepayment(
          customerName: 'Daw Mya', amount: 6000, method: 'kbzpay');

      final rows = await db.select(db.creditPayments).get();
      expect(rows.single.customerName, 'Daw Mya');
      expect(rows.single.amount, 6000);
      expect(rows.single.method, 'kbzpay');

      final outbox =
          (await db.select(db.outbox).get()).map((o) => o.entityTable).toSet();
      expect(outbox, contains('credit_payments'));
    });

    test('recordRepayment rejects non-positive amounts (audit H-3)',
        () async {
      await seedCreditSale('Ma Ma', 10000, 0);
      expect(
        () => credit.recordRepayment(customerName: 'Ma Ma', amount: 0),
        throwsArgumentError,
      );
      expect(
        () => credit.recordRepayment(customerName: 'Ma Ma', amount: -1000),
        throwsArgumentError,
      );
      // Nothing was written.
      expect(await db.select(db.creditPayments).get(), isEmpty);
    });

    test('recordRepayment rejects over-repayment beyond outstanding '
        '(audit H-3)', () async {
      await seedCreditSale('Ko Ko', 10000, 4000); // outstanding 6000
      // The dialog caps at outstanding; a modified client skipping it must
      // still be stopped at the repository layer.
      expect(
        () => credit.recordRepayment(
            customerName: 'Ko Ko', amount: 99999),
        throwsStateError,
      );
      expect(await db.select(db.creditPayments).get(), isEmpty);

      // A repayment within the balance is fine, and consumes the room.
      await credit.recordRepayment(customerName: 'Ko Ko', amount: 5000);
      expect(
        () =>
            credit.recordRepayment(customerName: 'Ko Ko', amount: 2000),
        throwsStateError,
      );
      // The remaining 1000 is still allowed.
      await credit.recordRepayment(customerName: 'Ko Ko', amount: 1000);
      expect((await db.select(db.creditPayments).get()).length, 2);
    });

    test('recordRepayment matches by directory id or typed name like the '
        'aggregate does', () async {
      await seedCreditSale('Mya Mya', 8000, 0);
      await credit.recordRepayment(customerName: '  mya mya ', amount: 3000);
      final customers = CreditRepository.aggregate(
        await credit.watchCreditSales().first,
        await credit.watchRepayments().first,
      );
      expect(customers.single.outstanding, 5000);
    });
  });
}
