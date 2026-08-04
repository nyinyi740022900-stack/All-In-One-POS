import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/accounts/payment_account_repository.dart';

Payment _payment(String method, int amount) => Payment(
      id: 'pay-$method-$amount',
      shopId: 'shop-1',
      saleId: 'sale-1',
      method: method,
      amount: amount,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
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
      date: DateTime(2026, 8, 1),
      accountId: accountId,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
      isDeleted: false,
      dirty: false,
    );

void main() {
  group('computeAccountBalance (pure)', () {
    test('opening balance + payments/repayments in this account − its expenses', () {
      final result = computeAccountBalance(
        openingBalance: 10000,
        payments: [_payment('kbzpay', 20000), _payment('cash', 5000)],
        repayments: [_repayment('kbzpay', 3000)],
        expenses: [_expense(4000, accountId: 'kbzpay')],
        accountId: 'kbzpay',
      );
      expect(result, 29000); // 10000 + 20000 + 3000 - 4000
    });

    test('other accounts and cash never leak into this account\'s balance', () {
      final result = computeAccountBalance(
        openingBalance: 0,
        payments: [_payment('cash', 50000), _payment('wavepay', 8000)],
        repayments: [_repayment('cash', 1000)],
        expenses: [_expense(2000, accountId: 'wavepay')],
        accountId: 'kbzpay',
      );
      expect(result, 0);
    });

    test('a cash expense (null accountId) never reduces a real account\'s balance', () {
      final result = computeAccountBalance(
        openingBalance: 5000,
        payments: [_payment('kbzpay', 1000)],
        repayments: const [],
        expenses: [_expense(3000)], // accountId: null → cash
        accountId: 'kbzpay',
      );
      expect(result, 6000); // the cash expense doesn't touch kbzpay
    });

    test('no activity: balance is just the opening balance', () {
      final result = computeAccountBalance(
        openingBalance: 15000,
        payments: const [],
        repayments: const [],
        expenses: const [],
        accountId: 'kbzpay',
      );
      expect(result, 15000);
    });
  });
}
