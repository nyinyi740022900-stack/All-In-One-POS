import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../analytics/analytics_providers.dart';
import 'expense_repository.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepository(
    ref.watch(databaseProvider),
    ref.watch(shopIdProvider),
  );
});

/// Expenses over the same range as the Analytics dashboard, so the two stay
/// in sync when the owner switches the today/week/month range there.
final expensesInRangeProvider = StreamProvider<List<Expense>>((ref) {
  final range = ref.watch(analyticsRangeProvider);
  final bounds = rangeBounds(range, DateTime.now());
  return ref
      .watch(expenseRepositoryProvider)
      .watchExpenses(bounds.start, bounds.end);
});

final expensesTotalProvider = Provider<int>((ref) {
  final expenses = ref.watch(expensesInRangeProvider).valueOrNull ?? const [];
  return expenses.fold(0, (sum, e) => sum + e.amount);
});
