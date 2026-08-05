import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../credit/credit_providers.dart';
import '../printing/printing_providers.dart';
import '../sell/sales_providers.dart';
import 'payment_account_repository.dart';

final paymentAccountRepositoryProvider = Provider<PaymentAccountRepository>((ref) {
  return PaymentAccountRepository(
    ref.watch(databaseProvider),
    ref.watch(shopIdProvider),
    ref.watch(settingsRepositoryProvider),
  );
});

final paymentAccountsProvider = StreamProvider<List<PaymentAccount>>((ref) {
  return ref.watch(paymentAccountRepositoryProvider).watchAccounts();
});

/// Payment-method ids to offer at checkout/repayment/order pickers: cash,
/// then every active Payment Account, in that order. `'credit'` is a
/// special non-money case some callers (checkout only) add themselves.
List<String> paymentMethodIds(List<PaymentAccount> accounts) =>
    ['cash', for (final a in accounts) a.id];

/// Live balance for one account. `payment_accounts` itself doesn't change
/// when a sale/repayment/expense/supplier-payment happens, so there's
/// nothing on that table to `watch()` — instead this re-fetches whenever
/// any of the inputs change, same shape as Cash Register's
/// `expectedCashProvider`.
final accountBalanceProvider =
    FutureProvider.family<int, PaymentAccount>((ref, account) async {
  ref.watch(salesStreamProvider);
  ref.watch(repaymentsProvider);
  ref.watch(_accountExpensesWatchProvider);
  ref.watch(_accountSupplierPaymentsWatchProvider);
  return ref.read(paymentAccountRepositoryProvider).balanceFor(account);
});

/// Invalidation-only signal — see [accountBalanceProvider].
final _accountExpensesWatchProvider = StreamProvider<List<Expense>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.expenses)
        ..where((t) => t.shopId.equals(shopId) & t.isDeleted.equals(false)))
      .watch();
});

/// Invalidation-only signal — see [accountBalanceProvider]. A supplier
/// payment made from an account is an outflow, same as an expense.
final _accountSupplierPaymentsWatchProvider =
    StreamProvider<List<SupplierPayment>>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return (db.select(db.supplierPayments)
        ..where((t) => t.shopId.equals(shopId) & t.isDeleted.equals(false)))
      .watch();
});

/// Seeds the 4 default accounts once per shop (no-op after the first
/// success) — fired once from its constructor, kept alive for the app's
/// lifetime via a `ref.watch` in `app.dart`, same shape as
/// `recurringExpenseGeneratorProvider`.
class PaymentAccountSeeder {
  PaymentAccountSeeder(Ref ref) {
    ref.read(paymentAccountRepositoryProvider).ensureDefaultsSeeded();
  }
}

final paymentAccountSeederProvider = Provider<PaymentAccountSeeder>((ref) {
  return PaymentAccountSeeder(ref);
});
