import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../credit/credit_providers.dart';
import '../sell/sales_providers.dart';
import 'cash_session_repository.dart';

final cashSessionRepositoryProvider = Provider<CashSessionRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final shopId = ref.watch(shopIdProvider);
  return CashSessionRepository(db, shopId);
});

final currentCashSessionProvider = StreamProvider<CashSession?>((ref) {
  return ref.watch(cashSessionRepositoryProvider).watchCurrentSession();
});

final cashSessionHistoryProvider = StreamProvider<List<CashSession>>((ref) {
  return ref.watch(cashSessionRepositoryProvider).watchSessions();
});

/// Settles [kCashSignalDebounce] after the last sale / repayment / expense
/// write, then bumps — so a checkout burst or a sync drain touching all
/// three tables triggers ONE drawer recompute instead of one per emission
/// (audit M7). Starts settled at 0 so the first read computes immediately.
const Duration kCashSignalDebounce = Duration(milliseconds: 250);

class _CashInputSignal extends StateNotifier<int> {
  _CashInputSignal(Ref ref) : super(0) {
    ref.listen(salesStreamProvider, (_, _) => _bump());
    ref.listen(repaymentsProvider, (_, _) => _bump());
    ref.listen(_cashExpensesWatchProvider, (_, _) => _bump());
    ref.listen(_cashSupplierPaymentsWatchProvider, (_, _) => _bump());
  }

  Timer? _timer;

  void _bump() {
    _timer?.cancel();
    _timer = Timer(kCashSignalDebounce, () {
      if (mounted) state++;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Invalidation-only counter — see [_CashInputSignal].
final cashInputSignalProvider =
    StateNotifierProvider<_CashInputSignal, int>((ref) => _CashInputSignal(ref));

/// Live "what the drawer should hold" for the current open session.
/// `cash_sessions` itself doesn't change when a sale/repayment/expense
/// happens, so there's nothing on that table to `watch()` — instead this
/// recomputes whenever the coalesced input signal settles (audit M7), then
/// re-reads fresh from the repository.
final expectedCashProvider = FutureProvider<int?>((ref) async {
  final session = ref.watch(currentCashSessionProvider).valueOrNull;
  if (session == null) return null;
  ref.watch(cashInputSignalProvider);
  return ref.read(cashSessionRepositoryProvider).expectedCash(session);
});

/// Invalidation-only signal — see [expectedCashProvider].
final _cashExpensesWatchProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(cashSessionRepositoryProvider).watchAllExpenses();
});

/// Invalidation-only signal — see [expectedCashProvider]. A cash-paid
/// supplier payment empties the till, so the drawer must recompute when one
/// is recorded. Mirrors [accountSupplierPaymentsWatchProvider] used by the
/// Payment Accounts balance; here it backs the Cash Register's [expectedCashProvider].
final _cashSupplierPaymentsWatchProvider =
    StreamProvider<List<SupplierPayment>>((ref) {
  return ref.watch(cashSessionRepositoryProvider).watchAllSupplierPayments();
});
