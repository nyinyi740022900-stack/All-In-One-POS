import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/expenses/recurring_expense_repository.dart';

void main() {
  late AppDatabase db;
  late RecurringExpenseRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RecurringExpenseRepository(db, 'shop-1');
  });

  tearDown(() async => db.close());

  test('upsertTemplate creates a row and enqueues outbox', () async {
    final id = await repo.upsertTemplate(category: 'rent', amount: 150000);
    final rows = await repo.watchTemplates().first;
    expect(rows, hasLength(1));
    expect(rows.single.id, id);
    expect(rows.single.amount, 150000);
    expect(rows.single.active, isTrue);

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
    final otherShop = RecurringExpenseRepository(db, 'shop-2');
    await otherShop.upsertTemplate(category: 'wages', amount: 80000);

    final rows = await repo.watchTemplates().first;
    expect(rows, hasLength(1));
    expect(rows.single.category, 'rent');
  });
}
