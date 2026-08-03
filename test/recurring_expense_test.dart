import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/expenses/expense_repository.dart';
import 'package:mm_pos/features/expenses/recurring_expense_repository.dart';

void main() {
  late AppDatabase db;
  late RecurringExpenseRepository repo;
  late ExpenseRepository expenseRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expenseRepo = ExpenseRepository(db, 'shop-1');
    repo = RecurringExpenseRepository(db, 'shop-1', expenseRepo);
  });

  tearDown(() async => db.close());

  test('upsertTemplate creates a row and enqueues outbox', () async {
    final id = await repo.upsertTemplate(category: 'rent', amount: 150000);
    final rows = await repo.watchTemplates().first;
    expect(rows, hasLength(1));
    expect(rows.single.id, id);
    expect(rows.single.amount, 150000);
    expect(rows.single.active, isTrue);
    expect(rows.single.autoGenerate, isFalse);

    final outbox = await db.select(db.outbox).get();
    expect(outbox.any((o) => o.entityTable == 'recurring_expenses'), isTrue);
  });

  test('upsertTemplate with an existing id updates in place (one row)',
      () async {
    final id = await repo.upsertTemplate(category: 'rent', amount: 150000);
    await repo.upsertTemplate(id: id, category: 'rent', amount: 160000);

    final rows = await repo.watchTemplates().first;
    expect(rows, hasLength(1));
    expect(rows.single.amount, 160000);
  });

  test('setActive toggles without touching other fields', () async {
    final id = await repo.upsertTemplate(category: 'wages', amount: 80000);
    await repo.setActive(id, false);

    final rows = await repo.watchTemplates().first;
    expect(rows.single.active, isFalse);
    expect(rows.single.amount, 80000);
  });

  test('deleteTemplate soft-deletes, excluded from watchTemplates', () async {
    final id = await repo.upsertTemplate(category: 'rent', amount: 150000);
    await repo.deleteTemplate(id);

    expect(await repo.watchTemplates().first, isEmpty);
    final raw = await (db.select(db.recurringExpenses)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    expect(raw.isDeleted, isTrue);
  });

  test('watchTemplates excludes other shops', () async {
    await repo.upsertTemplate(category: 'rent', amount: 150000);
    final otherShop =
        RecurringExpenseRepository(db, 'shop-2', ExpenseRepository(db, 'shop-2'));
    await otherShop.upsertTemplate(category: 'wages', amount: 80000);

    final rows = await repo.watchTemplates().first;
    expect(rows, hasLength(1));
    expect(rows.single.category, 'rent');
  });

  group('generateDueExpenses', () {
    test('month_start: not yet due before day 1 never happens, but a '
        'non-auto template never fires regardless of day', () async {
      await repo.upsertTemplate(
          category: 'rent', amount: 150000, autoGenerate: false);
      final fired =
          await repo.generateDueExpenses(now: DateTime(2026, 8, 15));
      expect(fired, isEmpty);
      expect(await expenseRepo.watchExpenses(DateTime(2026, 1), DateTime(2027)).first,
          isEmpty);
    });

    test('month_start: due on or after day 1, generates once and stamps '
        'lastGeneratedPeriod', () async {
      final id = await repo.upsertTemplate(
          category: 'rent',
          amount: 150000,
          autoGenerate: true,
          generationTiming: 'month_start');

      final fired =
          await repo.generateDueExpenses(now: DateTime(2026, 8, 3));
      expect(fired, hasLength(1));
      expect(fired.single.id, id);

      final expenses =
          await expenseRepo.watchExpenses(DateTime(2026, 8), DateTime(2026, 9)).first;
      expect(expenses, hasLength(1));
      expect(expenses.single.amount, 150000);

      final template = (await repo.watchTemplates().first).single;
      expect(template.lastGeneratedPeriod, '2026-08');
    });

    test('already generated this period: a second call does not duplicate',
        () async {
      await repo.upsertTemplate(
          category: 'rent',
          amount: 150000,
          autoGenerate: true,
          generationTiming: 'month_start');

      await repo.generateDueExpenses(now: DateTime(2026, 8, 3));
      final second = await repo.generateDueExpenses(now: DateTime(2026, 8, 20));
      expect(second, isEmpty);

      final expenses =
          await expenseRepo.watchExpenses(DateTime(2026, 8), DateTime(2026, 9)).first;
      expect(expenses, hasLength(1));
    });

    test('month_end: does not fire mid-month, fires on the actual last day',
        () async {
      await repo.upsertTemplate(
          category: 'wages',
          amount: 80000,
          autoGenerate: true,
          generationTiming: 'month_end');

      final midMonth = await repo.generateDueExpenses(now: DateTime(2026, 8, 15));
      expect(midMonth, isEmpty);

      // August 2026 has 31 days.
      final onLastDay = await repo.generateDueExpenses(now: DateTime(2026, 8, 31));
      expect(onLastDay, hasLength(1));
    });
  });
}
