import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

import '../../data/local/database.dart';
import '../accounts/payment_account_providers.dart';
import '../analytics/analytics_providers.dart';
import '../cash/cash_providers.dart';
import '../credit/credit_providers.dart';
import '../equity/equity_providers.dart';
import '../printing/printing_providers.dart' show settingsRepositoryProvider;
import '../suppliers/accounts_payable_providers.dart';
import 'balance_sheet.dart';
import 'cash_flow_calculator.dart';
import 'credit_aging.dart';

/// Inclusive start / exclusive end for the Cash Flow screen.
typedef CashFlowPeriod = ({DateTime start, DateTime endExclusive});

/// The Balance Sheet's figures, folded from the same live sources the
/// individual screens show: payment-account balances (the four flow tables
/// via [computeAccountBalance]), stock at cost, credit-book receivables,
/// supplier payables, owner paid-in capital and cumulative retained
/// earnings. Nothing new is stored — every ingredient's own provider
/// carries its invalidation signals, so this fold re-runs whenever any of
/// them changes.
final balanceSheetProvider = FutureProvider<BalanceSheet>((ref) async {
  final accounts = ref.watch(paymentAccountsProvider).valueOrNull ?? const [];
  var cashAndAccounts = 0;
  for (final a in accounts) {
    cashAndAccounts += await ref.watch(accountBalanceProvider(a).future);
  }
  // Physical till cash is not a PaymentAccount (Cash Register is a
  // separate ledger). Without this, a cash sale never moved the Balance
  // Sheet's cash line.
  ref.watch(currentCashSessionProvider);
  ref.watch(cashSessionHistoryProvider);
  ref.watch(cashInputSignalProvider);
  cashAndAccounts +=
      await ref.watch(cashSessionRepositoryProvider).physicalCashNow();

  final retained = await ref.watch(cumulativeNetProfitProvider.future);
  final paidIn =
      ref.watch(equitySummaryProvider).valueOrNull?.paidInCapital ?? 0;

  return BalanceSheet(
    cashAndAccounts: cashAndAccounts,
    inventoryValue: ref.watch(stockValueProvider),
    receivables: ref.watch(creditOutstandingTotalProvider),
    payables: ref
        .watch(supplierBalancesProvider)
        .fold(0, (sum, s) => sum + s.outstanding),
    paidInCapital: paidIn,
    retainedEarnings: retained,
  );
});

/// Per-account money movement for the Cash Flow screen, over the chosen
/// period. Folds the same tables [computeAccountBalance] does, split by
/// `createdAt` (the physical money moment — same call QA-M6 made for the
/// drawer). Owner contributions/drawings carry no account column and are
/// deliberately not part of this statement; the screen says so.
final cashFlowProvider =
    FutureProvider.family<List<AccountCashFlow>, CashFlowPeriod>(
        (ref, period) async {
  final accounts = ref.watch(paymentAccountsProvider).valueOrNull ?? const [];
  final payments =
      ref.watch(accountPaymentsWatchProvider).valueOrNull ?? const <Payment>[];
  final repayments =
      ref.watch(repaymentsProvider).valueOrNull ?? const <CreditPayment>[];
  final expenses =
      ref.watch(accountExpensesWatchProvider).valueOrNull ?? const <Expense>[];
  final supplierPayments = ref
      .watch(accountSupplierPaymentsWatchProvider)
      .valueOrNull ?? const <SupplierPayment>[];

  return computeCashFlows(
    accounts: accounts,
    payments: payments,
    repayments: repayments,
    expenses: expenses,
    supplierPayments: supplierPayments,
    start: period.start,
    endExclusive: period.endExclusive,
  );
});

/// Receivables aged into 0–30/31–60/61–90/90+ buckets, from the credit
/// book's own FIFO figures. Only rows still owing something appear.
final agedReceivablesProvider = Provider<List<AgedReceivable>>((ref) {
  final sales = ref.watch(creditSalesProvider).valueOrNull ?? const [];
  final owed = ref.watch(creditOwedBySaleProvider);
  return ageReceivables(
    creditSales: sales,
    owedBySaleId: owed,
    now: DateTime.now(),
  );
});

/// Σ outstanding per bucket (4 entries).
final agingTotalsProvider = Provider<List<int>>((ref) {
  return agingTotals(ref.watch(agedReceivablesProvider));
});

/// The shop's year-end close marker (ISO date, inclusive; null = books
/// open). Device-local per shop — see
/// [SettingsRepository.booksClosedThrough] for why this is not synced.
final booksClosedThroughProvider = FutureProvider<String?>((ref) async {
  final shopId = ref.watch(shopIdProvider);
  return ref.watch(settingsRepositoryProvider).booksClosedThrough(shopId);
});

/// True when [date] falls in a closed book — edits/deletes must be refused.
bool isDateInClosedBooks(String? closedThroughIso, DateTime? date) {
  if (closedThroughIso == null || closedThroughIso.isEmpty || date == null) {
    return false;
  }
  final closed = DateTime.tryParse(closedThroughIso);
  if (closed == null) return false;
  final endOfDay = DateTime(closed.year, closed.month, closed.day, 23, 59, 59);
  return !date.isAfter(endOfDay);
}
