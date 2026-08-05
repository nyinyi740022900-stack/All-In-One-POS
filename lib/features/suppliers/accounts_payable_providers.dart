import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import 'accounts_payable.dart';
import 'accounts_payable_repository.dart';

final accountsPayableRepositoryProvider =
    Provider<AccountsPayableRepository>((ref) {
  return AccountsPayableRepository(
    ref.watch(databaseProvider),
    ref.watch(shopIdProvider),
  );
});

final receivedPOsProvider = StreamProvider<List<PurchaseOrder>>((ref) {
  return ref.watch(accountsPayableRepositoryProvider).watchReceivedPOs();
});

final supplierPaymentsProvider = StreamProvider<List<SupplierPayment>>((ref) {
  return ref.watch(accountsPayableRepositoryProvider).watchPayments();
});

/// Per-supplier outstanding balances (suppliers still owed money, largest
/// first).
final supplierBalancesProvider = Provider<List<SupplierBalance>>((ref) {
  final pos = ref.watch(receivedPOsProvider).valueOrNull ?? const [];
  final payments = ref.watch(supplierPaymentsProvider).valueOrNull ?? const [];
  return aggregateAccountsPayable(pos, payments);
});

/// Every supplier who's ever had a received PO, including fully-paid-off
/// ones — same reasoning as Credit book's `allCreditCustomersProvider`.
final allSupplierBalancesProvider = Provider<List<SupplierBalance>>((ref) {
  final pos = ref.watch(receivedPOsProvider).valueOrNull ?? const [];
  final payments = ref.watch(supplierPaymentsProvider).valueOrNull ?? const [];
  return aggregateAccountsPayable(pos, payments, includeSettled: true);
});

/// Total Accounts Payable across all suppliers.
final accountsPayableTotalProvider = Provider<int>((ref) {
  return ref
      .watch(supplierBalancesProvider)
      .fold(0, (sum, b) => sum + b.outstanding);
});
