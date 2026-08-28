
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';
import 'expense_repository.dart';

/// Recurring monthly cost templates (rent, wages, etc.) — see
/// `RecurringExpenses` in tables.dart. Manual quick-fill by default;
/// [generateDueExpenses] handles the opt-in automatic path.
class RecurringExpenseRepository {
  RecurringExpenseRepository(this._db, this._shopId, this._expenseRepository);

  final AppDatabase _db;
  final String _shopId;
  final ExpenseRepository _expenseRepository;
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
    bool autoGenerate = false,
    String generationTiming = 'month_start',
    String? accountId,
    // Exists purely so tests can pick a deterministic date, same reason
    // generateDueExpenses takes one, rather than depending on the real
    // calendar — see the "justEnabled" catch-up guard below.
    DateTime? now,
  }) async {
    final templateId = id ?? _uuid.v4();
    final effectiveNow = now ?? DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.recurringExpenses)
            ..where((t) => t.id.equals(templateId)))
          .getSingleOrNull();

      // Turning auto-generate on (a new template, or re-enabling it) should
      // never immediately "catch up" for the current period if this
      // period's trigger day has already passed — wait for the next real
      // trigger instead of surprising the owner with an expense dated today
      // for a day that's already gone by.
      var lastGeneratedPeriod = existing?.lastGeneratedPeriod;
      final justEnabled = autoGenerate && existing?.autoGenerate != true;
      if (justEnabled) {
        final period =
            '${effectiveNow.year}-${effectiveNow.month.toString().padLeft(2, '0')}';
        final lastDayOfMonth =
            DateTime(effectiveNow.year, effectiveNow.month + 1, 0).day;
        final triggerDay =
            generationTiming == 'month_end' ? lastDayOfMonth : 1;
        if (effectiveNow.day >= triggerDay) lastGeneratedPeriod = period;
      }

      await _db.into(_db.recurringExpenses).insertOnConflictUpdate(
            RecurringExpensesCompanion(
              id: Value(templateId),
              shopId: Value(_shopId),
              category: Value(category),
              amount: Value(amount),
              note: Value(note),
              active: Value(active),
              autoGenerate: Value(autoGenerate),
              generationTiming: Value(generationTiming),
              lastGeneratedPeriod: Value(lastGeneratedPeriod),
              accountId: Value(accountId),
              updatedAt: Value(effectiveNow),
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

  /// Generates an `Expense` for every active, auto-generate-on template
  /// that's reached its trigger day this month and hasn't already fired for
  /// it — 'month_start' triggers on day 1, 'month_end' on the month's
  /// actual last day (28-31). Stamps `lastGeneratedPeriod` so the same
  /// month never double-fires, even across multiple app opens. Returns the
  /// templates it fired for (empty if nothing was due), which the caller
  /// uses to show a one-time notice.
  Future<List<RecurringExpense>> generateDueExpenses({DateTime? now}) async {
    final effectiveNow = now ?? DateTime.now();
    final period =
        '${effectiveNow.year}-${effectiveNow.month.toString().padLeft(2, '0')}';
    final lastDayOfMonth =
        DateTime(effectiveNow.year, effectiveNow.month + 1, 0).day;

    final templates = await (_db.select(_db.recurringExpenses)
          ..where((t) =>
              t.shopId.equals(_shopId) &
              t.isDeleted.equals(false) &
              t.active.equals(true) &
              t.autoGenerate.equals(true)))
        .get();

    final fired = <RecurringExpense>[];
    for (final t in templates) {
      if (t.lastGeneratedPeriod == period) continue;
      final triggerDay =
          t.generationTiming == 'month_end' ? lastDayOfMonth : 1;
      if (effectiveNow.day < triggerDay) continue;

      await _expenseRepository.upsertExpense(
        // Deterministic id (audit QA-M1): two offline devices reaching the
        // same trigger day both mint 'auto-<template>-<period>', so their
        // sync upserts converge on ONE remote expense row instead of
        // double-charging rent for a month.
        id: 'auto-${t.id}-$period',
        category: t.category,
        amount: t.amount,
        date: effectiveNow,
        note: t.note,
        accountId: t.accountId,
      );
      await _db.transaction(() async {
        await (_db.update(_db.recurringExpenses)
              ..where((row) => row.id.equals(t.id)))
            .write(RecurringExpensesCompanion(
          lastGeneratedPeriod: Value(period),
          updatedAt: Value(effectiveNow),
          dirty: const Value(true),
        ));
        await _enqueue(t.id);
      });
      fired.add(t);
    }
    return fired;
  }

  Future<void> _enqueue(String id) async {
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'recurring_expenses',
          rowId: id,
          op: 'upsert',
        ));
  }
}
