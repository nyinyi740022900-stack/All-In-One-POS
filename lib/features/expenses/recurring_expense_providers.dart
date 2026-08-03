import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import 'recurring_expense_repository.dart';

final recurringExpenseRepositoryProvider =
    Provider<RecurringExpenseRepository>((ref) {
  return RecurringExpenseRepository(
    ref.watch(databaseProvider),
    ref.watch(shopIdProvider),
  );
});

final recurringExpenseTemplatesProvider =
    StreamProvider<List<RecurringExpense>>((ref) {
  return ref.watch(recurringExpenseRepositoryProvider).watchTemplates();
});
