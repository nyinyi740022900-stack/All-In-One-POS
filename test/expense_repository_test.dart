import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/expenses/expense_repository.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ExpenseRepository(db, 'shop-1');
  });

  tearDown(() async => db.close());

  test('upsertExpense persists and enqueues outbox', () async {
    final id = await repo.upsertExpense(
      category: 'rent',
      amount: 150000,
      date: DateTime(2026, 7, 1),
      note: 'July rent',
    );
    final rows = await db.select(db.expenses).get();
    final e = rows.firstWhere((r) => r.id == id);
    expect(e.category, 'rent');
    expect(e.amount, 150000);
    expect(e.note, 'July rent');
    expect(e.receiptPhotoPath, isNull);

    final outbox = await db.select(db.outbox).get();
    expect(outbox.any((o) => o.entityTable == 'expenses'), isTrue);
  });

  test('upsertExpense with an existing id edits in place instead of adding '
      'a second row', () async {
    final id = await repo.upsertExpense(
      category: 'wages',
      amount: 50000,
      date: DateTime(2026, 7, 2),
    );
    await repo.upsertExpense(
      id: id,
      category: 'wages',
      amount: 60000,
      date: DateTime(2026, 7, 2),
      note: 'corrected amount',
    );
    final rows = await db.select(db.expenses).get();
    expect(rows, hasLength(1));
    expect(rows.first.amount, 60000);
    expect(rows.first.note, 'corrected amount');
  });

  test('watchExpenses filters to the given date range and excludes deleted',
      () async {
    await repo.upsertExpense(
        category: 'rent', amount: 1000, date: DateTime(2026, 7, 1));
    final inRange = await repo.upsertExpense(
        category: 'utilities', amount: 2000, date: DateTime(2026, 7, 5));
    await repo.upsertExpense(
        category: 'transport', amount: 3000, date: DateTime(2026, 7, 20));

    final result = await repo
        .watchExpenses(DateTime(2026, 7, 3), DateTime(2026, 7, 10))
        .first;
    expect(result, hasLength(1));
    expect(result.first.id, inRange);

    await repo.deleteExpense(inRange);
    final afterDelete = await repo
        .watchExpenses(DateTime(2026, 7, 3), DateTime(2026, 7, 10))
        .first;
    expect(afterDelete, isEmpty);
  });
}
