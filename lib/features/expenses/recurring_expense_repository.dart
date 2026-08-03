import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// Recurring monthly cost templates (rent, wages, etc.) — see
/// `RecurringExpenses` in tables.dart for why this is quick-fill, not
/// auto-generated.
class RecurringExpenseRepository {
  RecurringExpenseRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  Stream<List<RecurringExpense>> watchTemplates() {
    return (_db.select(_db.recurringExpenses)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.category)]))
        .watch();
  }

  Future<String> upsertTemplate({
    String? id,
    required String category,
    required int amount,
    String? note,
    bool active = true,
  }) async {
    final templateId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.recurringExpenses).insertOnConflictUpdate(
            RecurringExpensesCompanion(
              id: Value(templateId),
              shopId: Value(_shopId),
              category: Value(category),
              amount: Value(amount),
              note: Value(note),
              active: Value(active),
              updatedAt: Value(now),
              dirty: const Value(true),
            ),
          );
      await _enqueue(templateId);
    });
    return templateId;
  }

  Future<void> setActive(String id, bool active) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.recurringExpenses)..where((t) => t.id.equals(id)))
          .write(RecurringExpensesCompanion(
        active: Value(active),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue(id);
    });
  }

  Future<void> deleteTemplate(String id) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.recurringExpenses)..where((t) => t.id.equals(id)))
          .write(RecurringExpensesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue(id);
    });
  }

  Future<void> _enqueue(String id) async {
    final row = await (_db.select(_db.recurringExpenses)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'recurring_expenses',
          rowId: id,
          op: 'upsert',
          payload: jsonEncode(row.toJson()),
        ));
  }
}
