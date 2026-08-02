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

/// Live "what the drawer should hold" for the current open session.
/// `cash_sessions` itself doesn't change when a sale/repayment/expense
/// happens, so there's nothing on that table to `watch()` — instead this
/// re-fetches whenever any of the three inputs to the calculation change.
final expectedCashProvider = FutureProvider<int?>((ref) async {
  final session = ref.watch(currentCashSessionProvider).valueOrNull;
  if (session == null) return null;
  ref.watch(salesStreamProvider);
  ref.watch(repaymentsProvider);
  ref.watch(_cashExpensesWatchProvider);
  return ref.read(cashSessionRepositoryProvider).expectedCash(session);
});

/// Invalidation-only signal — see [expectedCashProvider].
final _cashExpensesWatchProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(cashSessionRepositoryProvider).watchAllExpenses();
});
