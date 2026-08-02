import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import 'credit_repository.dart';

final creditRepositoryProvider = Provider<CreditRepository>((ref) {
  return CreditRepository(
    ref.watch(databaseProvider),
    ref.watch(shopIdProvider),
  );
});

final creditSalesProvider = StreamProvider<List<Sale>>((ref) {
  return ref.watch(creditRepositoryProvider).watchCreditSales();
});

final repaymentsProvider = StreamProvider<List<CreditPayment>>((ref) {
  return ref.watch(creditRepositoryProvider).watchRepayments();
});

/// Per-customer outstanding balances (customers who still owe, largest first).
final creditCustomersProvider = Provider<List<CreditCustomer>>((ref) {
  final sales = ref.watch(creditSalesProvider).valueOrNull ?? const [];
  final repayments = ref.watch(repaymentsProvider).valueOrNull ?? const [];
  return CreditRepository.aggregate(sales, repayments);
});

/// Every customer who has ever had a credit sale, including ones fully paid
/// off — backs the credit book's "All" filter so a settled customer's
/// repayment history (exact date/time of each payment) stays reachable
/// instead of disappearing once their balance hits 0.
final allCreditCustomersProvider = Provider<List<CreditCustomer>>((ref) {
  final sales = ref.watch(creditSalesProvider).valueOrNull ?? const [];
  final repayments = ref.watch(repaymentsProvider).valueOrNull ?? const [];
  return CreditRepository.aggregate(sales, repayments, includeSettled: true);
});

enum CreditFilter { outstanding, all }

final creditFilterProvider =
    StateProvider<CreditFilter>((ref) => CreditFilter.outstanding);

/// Total credit outstanding across all customers.
final creditOutstandingTotalProvider = Provider<int>((ref) {
  return ref
      .watch(creditCustomersProvider)
      .fold(0, (sum, c) => sum + c.outstanding);
});

/// Remaining owed per sale id after allocating repayments (FIFO per customer).
/// Used to hide credit invoices once they've been paid off in the credit book.
final creditOwedBySaleProvider = Provider<Map<String, int>>((ref) {
  final sales = ref.watch(creditSalesProvider).valueOrNull ?? const [];
  final repayments = ref.watch(repaymentsProvider).valueOrNull ?? const [];
  return CreditRepository.owedBySale(sales, repayments);
});
