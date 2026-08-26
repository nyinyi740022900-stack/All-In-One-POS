import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/cash/cash_session_repository.dart';

Payment _payment(String method, int amount, {DateTime? at}) => Payment(
      id: 'pay-$method-$amount-${at?.millisecondsSinceEpoch}',
      shopId: 'shop-1',
      saleId: 'sale-1',
      method: method,
      amount: amount,
      createdAt: at ?? DateTime(2026, 8, 1),
      updatedAt: at ?? DateTime(2026, 8, 1),
      isDeleted: false,
      dirty: false,
    );

CreditPayment _repayment(String method, int amount) => CreditPayment(
      id: 'repay-$method-$amount',
      shopId: 'shop-1',
      customerName: 'Aung',
      method: method,
      amount: amount,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      isDeleted: false,
      dirty: false,
    );

Expense _expense(int amount, {String? accountId}) => Expense(
      id: 'exp-$amount-${accountId ?? 'cash'}',
      shopId: 'shop-1',
      category: 'other',
      amount: amount,
      accountId: accountId,
      date: DateTime(2026, 8, 1),
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      isDeleted: false,
      dirty: false,
    );

SupplierPayment _supplierPayment(String method, int amount) =>
    SupplierPayment(
      id: 'sp-$method-$amount',
      shopId: 'shop-1',
      supplierName: 'Acme',
      method: method,
      amount: amount,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      isDeleted: false,
      dirty: false,
    );

void main() {
  group('computeExpectedCash (pure)', () {
    test('opening + cash payments − expenses, non-cash tenders ignored', () {
      final result = computeExpectedCash(
        openingAmount: 50000,
        payments: [_payment('cash', 10000), _payment('kbzpay', 20000)],
        repayments: const [],
        expenses: [_expense(3000)],
        supplierPayments: const [],
      );
      expect(result, 57000); // 50000 + 10000 - 3000
    });

    test('cash credit-repayments count as cash in too', () {
      final result = computeExpectedCash(
        openingAmount: 0,
        payments: const [],
        repayments: [_repayment('cash', 5000), _repayment('wavepay', 9000)],
        expenses: const [],
        supplierPayments: const [],
      );
      expect(result, 5000);
    });

    test('a refund (negative-amount cash payment) reduces expected cash', () {
      final result = computeExpectedCash(
        openingAmount: 10000,
        payments: [_payment('cash', 7000), _payment('cash', -7000)],
        repayments: const [],
        expenses: const [],
        supplierPayments: const [],
      );
      expect(result, 10000);
    });

    test('an expense paid from a non-cash account does not reduce expected '
        'cash', () {
      final result = computeExpectedCash(
        openingAmount: 50000,
        payments: [_payment('cash', 10000)],
        repayments: const [],
        expenses: [_expense(3000, accountId: 'kbzpay')],
        supplierPayments: const [],
      );
      expect(result, 60000); // 50000 + 10000, the 3000 expense is ignored
    });

    test('only cash supplier payments reduce expected cash', () {
      final result = computeExpectedCash(
        openingAmount: 50000,
        payments: [_payment('cash', 10000)],
        repayments: const [],
        expenses: const [],
        supplierPayments: [_supplierPayment('cash', 3000),
                           _supplierPayment('kbzpay', 7000)],
      );
      expect(result, 57000); // 50000 + 10000 - 3000 (cash sp only)
    });

    test('no activity: expected cash is just the opening float', () {
      final result = computeExpectedCash(
        openingAmount: 20000,
        payments: const [],
        repayments: const [],
        expenses: const [],
        supplierPayments: const [],
      );
      expect(result, 20000);
    });
  });

  group('CashSessionRepository', () {
    late AppDatabase db;
    late CashSessionRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = CashSessionRepository(db, 'shop-1');
    });

    tearDown(() async => db.close());

    test('openSession persists, watchCurrentSession finds it, and enqueues '
        'outbox', () async {
      final id = await repo.openSession(openingAmount: 30000, note: 'AM');
      final current = await repo.watchCurrentSession().first;
      expect(current, isNotNull);
      expect(current!.id, id);
      expect(current.openingAmount, 30000);
      expect(current.closedAt, isNull);

      final outbox = await db.select(db.outbox).get();
      expect(outbox.any((o) => o.entityTable == 'cash_sessions'), isTrue);
    });

    test('closeSession clears watchCurrentSession and records the closing '
        'amount', () async {
      final id = await repo.openSession(openingAmount: 30000);
      await repo.closeSession(id, closingAmount: 29500, note: 'short 500');

      expect(await repo.watchCurrentSession().first, isNull);
      final history = await repo.watchSessions().first;
      expect(history.single.closingAmount, 29500);
      expect(history.single.note, 'short 500');
    });

    test('expectedCash reflects sales/repayments/expenses recorded after '
        'the session opened', () async {
      final id = await repo.openSession(openingAmount: 10000);
      final session = await repo.watchCurrentSession().first;

      await db.into(db.payments).insert(PaymentsCompanion.insert(
            id: 'p1',
            shopId: 'shop-1',
            saleId: 'sale-1',
            method: 'cash',
            amount: 5000,
          ));
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
            id: 'e1',
            shopId: 'shop-1',
            category: 'other',
            amount: 2000,
            date: DateTime.now(),
          ));

      final expected = await repo.expectedCash(session!);
      expect(expected, 13000); // 10000 + 5000 - 2000
      expect(id, isNotEmpty);
    });

    group('reportFor', () {
      test('breaks down the same window expectedCash collapses to one int',
          () async {
        final id = await repo.openSession(openingAmount: 10000);
        final session = await repo.watchCurrentSession().first;

        await db.into(db.payments).insert(PaymentsCompanion.insert(
              id: 'p1',
              shopId: 'shop-1',
              saleId: 'sale-1',
              method: 'cash',
              amount: 5000,
            ));
        await db.into(db.creditPayments).insert(
              CreditPaymentsCompanion.insert(
                id: 'r1',
                shopId: 'shop-1',
                customerName: 'Aung',
                method: const Value('cash'),
                amount: 1000,
              ),
            );
        await db.into(db.expenses).insert(ExpensesCompanion.insert(
              id: 'e1',
              shopId: 'shop-1',
              category: 'other',
              amount: 2000,
              date: DateTime.now(),
            ));
        await db.into(db.expenses).insert(ExpensesCompanion.insert(
              id: 'e2',
              shopId: 'shop-1',
              category: 'other',
              amount: 9000,
              accountId: const Value('kbzpay'),
              date: DateTime.now(),
            ));

        final report = await repo.reportFor(session!);
        expect(report.openingAmount, 10000);
        expect(report.cashSalesTotal, 5000);
        expect(report.cashRepaymentsTotal, 1000);
        expect(report.expensesTotal, 2000); // the kbzpay-paid e2 is excluded
        expect(report.expectedCash, 14000); // 10000 + 5000 + 1000 - 2000
        expect(report.closingAmount, isNull);
        expect(report.variance, isNull);
        expect(id, isNotEmpty);
      });

      test('closingAmount/variance are populated once the session is closed',
          () async {
        // Explicit timestamps throughout (rather than relying on
        // openSession/closeSession's DateTime.now()) so the payment falls
        // deterministically inside the window regardless of wall-clock
        // timing.
        final opened = DateTime(2026, 8, 1, 9);
        final closed = DateTime(2026, 8, 1, 20);
        await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
              id: 's1',
              shopId: 'shop-1',
              openedAt: opened,
              openingAmount: 10000,
              closedAt: Value(closed),
              closingAmount: const Value(14500),
            ));
        await db.into(db.payments).insert(PaymentsCompanion.insert(
              id: 'p1',
              shopId: 'shop-1',
              saleId: 'sale-1',
              method: 'cash',
              amount: 5000,
              createdAt: Value(DateTime(2026, 8, 1, 12)),
            ));

        final session =
            (await db.select(db.cashSessions).get()).single;
        final report = await repo.reportFor(session);
        expect(report.expectedCash, 15000); // 10000 + 5000
        expect(report.closingAmount, 14500);
        expect(report.variance, -500); // short by 500
      });
    });
  });
}
