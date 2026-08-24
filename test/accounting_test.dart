import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/accounting/accounting_providers.dart';
import 'package:mm_pos/features/accounting/balance_sheet.dart';
import 'package:mm_pos/features/accounting/cash_flow_calculator.dart';
import 'package:mm_pos/features/accounting/credit_aging.dart';

PaymentAccount _account(String id, {int opening = 0}) => PaymentAccount(
      id: id,
      shopId: 'shop-1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      isDeleted: false,
      dirty: false,
      name: 'Acc-$id',
      openingBalance: opening,
    );

Payment _tender(String method, int amount, DateTime at) => Payment(
      id: 'pay-$method-$amount-${at.millisecondsSinceEpoch}',
      shopId: 'shop-1',
      createdAt: at,
      updatedAt: at,
      isDeleted: false,
      dirty: false,
      saleId: 's',
      method: method,
      amount: amount,
    );

CreditPayment _repayment(String method, int amount, DateTime at) =>
    CreditPayment(
      id: 'rep-$amount-${at.millisecondsSinceEpoch}',
      shopId: 'shop-1',
      createdAt: at,
      updatedAt: at,
      isDeleted: false,
      dirty: false,
      customerName: 'c',
      method: method,
      amount: amount,
    );

Expense _expense(String? accountId, int amount, DateTime createdAt) =>
    Expense(
      id: 'exp-$amount-${createdAt.millisecondsSinceEpoch}',
      shopId: 'shop-1',
      createdAt: createdAt,
      updatedAt: createdAt,
      isDeleted: false,
      dirty: false,
      date: DateTime(2026, 8, 1),
      category: 'other',
      amount: amount,
      accountId: accountId,
    );

SupplierPayment _supplierPayment(String method, int amount, DateTime at) =>
    SupplierPayment(
      id: 'sp-$amount-${at.millisecondsSinceEpoch}',
      shopId: 'shop-1',
      createdAt: at,
      updatedAt: at,
      isDeleted: false,
      dirty: false,
      supplierName: 's',
      method: method,
      amount: amount,
    );

Sale _creditSale(String id, DateTime finalizedAt, int total, int paid) => Sale(
      id: id,
      shopId: 'shop-1',
      createdAt: finalizedAt,
      updatedAt: finalizedAt,
      isDeleted: false,
      dirty: false,
      invoiceNo: 'INV-$id',
      subtotal: total,
      discount: 0,
      changeDue: 0,
      total: total,
      paid: paid,
      paymentMethod: 'credit',
      finalizedAt: finalizedAt,
    );

void main() {
  group('computeCashFlows (period boundaries + per-account fold)', () {
    final start = DateTime(2026, 8, 1);
    final endExclusive = DateTime(2026, 9, 1);
    final july = DateTime(2026, 7, 15);
    final aug = DateTime(2026, 8, 10);
    final sep = DateTime(2026, 9, 2);

    test('opening folds pre-period flows, in/out only inside the window', () {
      final flows = computeCashFlows(
        accounts: [_account('cash', opening: 1000)],
        payments: [
          _tender('cash', 500, july), // → opening
          _tender('cash', 700, aug), // → inflow
          _tender('cash', 100, sep), // → outside, ignored
        ],
        repayments: [_repayment('cash', 300, aug)],
        expenses: [_expense('cash', 200, july), _expense('cash', 50, aug)],
        supplierPayments: [_supplierPayment('cash', 400, aug)],
        start: start,
        endExclusive: endExclusive,
      );
      expect(flows, hasLength(1));
      final f = flows.single;
      expect(f.opening, 1000 + 500 - 200);
      expect(f.inflow, 700 + 300);
      expect(f.outflow, 50 + 400);
      expect(f.closing, f.opening + f.inflow - f.outflow);
    });

    test('accounts never touched stay at their opening balance', () {
      final flows = computeCashFlows(
        accounts: [_account('kbz'), _account('wave', opening: 999)],
        payments: const [],
        repayments: const [],
        expenses: const [],
        supplierPayments: const [],
        start: start,
        endExclusive: endExclusive,
      );
      expect(flows[0].closing, 0);
      expect(flows[1].closing, 999);
    });
  });

  group('credit aging', () {
    final now = DateTime(2026, 8, 24);

    test('buckets by days since the sale, 90+ open-ended', () {
      expect(agingBucketFor(now.subtract(const Duration(days: 0)), now), 0);
      expect(agingBucketFor(now.subtract(const Duration(days: 30)), now), 0);
      expect(agingBucketFor(now.subtract(const Duration(days: 31)), now), 1);
      expect(agingBucketFor(now.subtract(const Duration(days: 61)), now), 2);
      expect(agingBucketFor(now.subtract(const Duration(days: 91)), now), 3);
    });

    test('settled and over-allocated debts drop out; totals sum per bucket',
        () {
      final rows = ageReceivables(
        creditSales: [
          _creditSale('a', now.subtract(const Duration(days: 10)), 5000, 0),
          _creditSale('b', now.subtract(const Duration(days: 45)), 8000, 0),
          _creditSale('c', now.subtract(const Duration(days: 100)), 3000, 0),
          _creditSale('settled', now.subtract(const Duration(days: 5)),
              4000, 4000), // fully paid → hidden
        ],
        owedBySaleId: {
          'a': 5000,
          'b': 8000,
          'c': 3000,
          // 'settled' absent → raw total-paid = 0 → hidden
        },
        now: now,
      );
      expect(rows, hasLength(3));
      final totals = agingTotals(rows);
      expect(totals, [5000, 8000, 0, 3000]);
    });

    test('FIFO allocation map wins over the stale raw difference', () {
      final rows = ageReceivables(
        creditSales: [
          _creditSale('x', now.subtract(const Duration(days: 10)), 10000, 0),
        ],
        owedBySaleId: const {'x': 2500}, // repaid 7500 via the credit book
        now: now,
      );
      expect(rows.single.outstanding, 2500);
    });
  });

  group('balance sheet', () {
    test('assets/liabilities/equity fold; untracked is honest, not forced',
        () {
      const sheet = BalanceSheet(
        cashAndAccounts: 1000,
        inventoryValue: 5000,
        receivables: 2000,
        payables: 1500,
        paidInCapital: 3000,
        retainedEarnings: 1000,
      );
      expect(sheet.assets, 8000);
      expect(sheet.equityTotal, 4000);
      // 8000 − 1500 − 4000 = 2500 (e.g. hand-entered opening stock).
      expect(sheet.untracked, 2500);
    });
  });

  group('year-end close guard', () {
    test('closed-through date is inclusive to the end of that day', () {
      expect(isDateInClosedBooks('2025-12-31', DateTime(2025, 12, 31)), isTrue);
      expect(
        isDateInClosedBooks(
          '2025-12-31',
          DateTime(2025, 12, 31, 23, 59, 59),
        ),
        isTrue,
      );
      expect(isDateInClosedBooks('2025-12-31', DateTime(2026, 1, 1)), isFalse);
      expect(isDateInClosedBooks(null, DateTime(2025)), isFalse);
      expect(isDateInClosedBooks('2025-12-31', null), isFalse);
      expect(isDateInClosedBooks('not-a-date', DateTime(2020)), isFalse);
    });
  });
}
