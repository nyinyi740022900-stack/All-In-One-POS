import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// Owner capital contributions and drawings — deliberately separate from
/// `ExpenseRepository` (see the doc comment on `EquityEntries` in
/// tables.dart). Same simple dated-list CRUD shape as `ExpenseRepository`.
class EquityRepository {
  EquityRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  Stream<List<EquityEntry>> watchEntries() {
    return (_db.select(_db.equityEntries)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .watch();
  }

  Future<String> addEntry({
    String? id,
    required String type,
    required int amount,
    required DateTime date,
    String? note,
  }) async {
    final entryId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.equityEntries).insertOnConflictUpdate(
            EquityEntriesCompanion(
              id: Value(entryId),
              shopId: Value(_shopId),
              type: Value(type),
              amount: Value(amount),
              date: Value(date),
              note: Value(note),
              updatedAt: Value(now),
              dirty: const Value(true),
            ),
          );
      await _enqueue(entryId);
    });
    return entryId;
  }

  Future<void> deleteEntry(String id) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.equityEntries)..where((t) => t.id.equals(id)))
          .write(EquityEntriesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue(id);
    });
  }

  Future<void> _enqueue(String id) async {
    final row = await (_db.select(_db.equityEntries)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'equity_entries',
          rowId: id,
          op: 'upsert',
          payload: jsonEncode(row.toJson()),
        ));
  }
}
