import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// rent | utilities | wages | transport | packaging | other
const expenseCategories = [
  'rent',
  'utilities',
  'wages',
  'transport',
  'packaging',
  'other',
];

/// The shop's non-inventory operating expenses. See `Expenses` in
/// tables.dart for why restock cost is deliberately excluded.
class ExpenseRepository {
  ExpenseRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  Stream<List<Expense>> watchExpenses(DateTime start, DateTime end) {
    return (_db.select(_db.expenses)
          ..where((t) =>
              t.shopId.equals(_shopId) &
              t.isDeleted.equals(false) &
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .watch();
  }

  Future<String> upsertExpense({
    String? id,
    required String category,
    required int amount,
    required DateTime date,
    String? note,
    String? receiptPhotoPath,
  }) async {
    final expenseId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.expenses).insertOnConflictUpdate(ExpensesCompanion(
            id: Value(expenseId),
            shopId: Value(_shopId),
            category: Value(category),
            amount: Value(amount),
            date: Value(date),
            note: Value(note),
            receiptPhotoPath: Value(receiptPhotoPath),
            updatedAt: Value(now),
            dirty: const Value(true),
          ));
      await _enqueue(expenseId);
    });
    return expenseId;
  }

  Future<void> deleteExpense(String id) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.expenses)..where((t) => t.id.equals(id)))
          .write(ExpensesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue(id);
    });
  }

  /// Saves a receipt photo to this device's local storage (never uploaded —
  /// see the doc comment on `Expenses`) and returns its path. Compresses
  /// first so it doesn't eat phone storage the way a raw camera photo would.
  Future<String> saveReceiptPhoto(List<int> bytes, {String ext = 'jpg'}) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'expense_receipts'));
    if (!await folder.exists()) await folder.create(recursive: true);
    final file = File(p.join(
        folder.path, 'r-${DateTime.now().microsecondsSinceEpoch}.$ext'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<void> _enqueue(String id) async {
    final row = await (_db.select(_db.expenses)..where((t) => t.id.equals(id)))
        .getSingle();
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'expenses',
          rowId: id,
          op: 'upsert',
          payload: jsonEncode(row.toJson()),
        ));
  }
}
