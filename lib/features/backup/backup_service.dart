import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/database.dart';

/// Import/export of the shop's business data as a single JSON file.
///
/// The backup covers the ledger tables (products, sales, stock, credit, …) but
/// deliberately excludes device-local state — `app_settings` (device id,
/// license cache, printer config) and the `outbox` — so restoring a backup on
/// the same device never clobbers its identity or pending sync queue.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const formatVersion = 1;

  Future<Map<String, List<Map<String, dynamic>>>> _readAll() async {
    return {
      'categories': (await _db.select(_db.categories).get())
          .map((r) => r.toJson())
          .toList(),
      'products':
          (await _db.select(_db.products).get()).map((r) => r.toJson()).toList(),
      'stock_levels': (await _db.select(_db.stockLevels).get())
          .map((r) => r.toJson())
          .toList(),
      'stock_movements': (await _db.select(_db.stockMovements).get())
          .map((r) => r.toJson())
          .toList(),
      'sales':
          (await _db.select(_db.sales).get()).map((r) => r.toJson()).toList(),
      'sale_items': (await _db.select(_db.saleItems).get())
          .map((r) => r.toJson())
          .toList(),
      'payments': (await _db.select(_db.payments).get())
          .map((r) => r.toJson())
          .toList(),
      'credit_payments': (await _db.select(_db.creditPayments).get())
          .map((r) => r.toJson())
          .toList(),
      'license_payments': (await _db.select(_db.licensePayments).get())
          .map((r) => r.toJson())
          .toList(),
      // Receipt photos themselves are local files, not included here (see
      // Expenses' doc comment in tables.dart) — only the expense record
      // (amount/category/date/note) round-trips through a backup.
      'expenses':
          (await _db.select(_db.expenses).get()).map((r) => r.toJson()).toList(),
    };
  }

  /// Serializes the whole business dataset to a pretty JSON string.
  Future<String> exportJson() async {
    final tables = await _readAll();
    final total = tables.values.fold<int>(0, (s, l) => s + l.length);
    final envelope = {
      'app': 'mm_pos',
      'formatVersion': formatVersion,
      'schemaVersion': _db.schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'rowCount': total,
      'tables': tables,
    };
    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Writes a backup file to the temp dir and returns it (for sharing).
  Future<File> writeBackupFile() async {
    final json = await exportJson();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File(p.join(dir.path, 'mmpos-backup-$stamp.json'));
    await file.writeAsString(json);
    return file;
  }

  /// Restores a backup, **replacing** all business data. Device settings,
  /// license, and the outbox are left untouched. Runs in one transaction so a
  /// bad file can never leave a half-restored database. Returns rows written.
  ///
  /// Every restored row is stamped with a fresh `updatedAt` and re-enqueued
  /// to the outbox — restoring is itself a write. Without this, the restore
  /// would only ever be local: the next sync pull could silently overwrite
  /// it with whatever's still on the server (last-write-wins on the
  /// backup's old timestamps), and other devices on this shop would never
  /// see it at all.
  Future<int> importReplaceAll(String jsonStr) async {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map || decoded['app'] != 'mm_pos') {
      throw const FormatException('Not an MM POS backup file.');
    }
    final tables = (decoded['tables'] as Map).cast<String, dynamic>();
    List<Map<String, dynamic>> rows(String name) =>
        ((tables[name] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();

    var written = 0;
    final now = DateTime.now();
    await _db.transaction(() async {
      // Clear existing business data (no FKs, so order is irrelevant).
      await _db.delete(_db.saleItems).go();
      await _db.delete(_db.payments).go();
      await _db.delete(_db.sales).go();
      await _db.delete(_db.stockMovements).go();
      await _db.delete(_db.stockLevels).go();
      await _db.delete(_db.products).go();
      await _db.delete(_db.categories).go();
      await _db.delete(_db.creditPayments).go();
      await _db.delete(_db.licensePayments).go();
      await _db.delete(_db.expenses).go();

      for (final m in rows('categories')) {
        final row = Category.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.categories).insert(row);
        await _enqueue('categories', row.id, row.toJson());
        written++;
      }
      for (final m in rows('products')) {
        final row = Product.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.products).insert(row);
        await _enqueue('products', row.id, row.toJson());
        written++;
      }
      for (final m in rows('stock_levels')) {
        final row =
            StockLevel.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.stockLevels).insert(row);
        await _enqueue('stock_levels', row.id, row.toJson());
        written++;
      }
      for (final m in rows('stock_movements')) {
        final row =
            StockMovement.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.stockMovements).insert(row);
        await _enqueue('stock_movements', row.id, row.toJson());
        written++;
      }
      for (final m in rows('sales')) {
        final row = Sale.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.sales).insert(row);
        await _enqueue('sales', row.id, row.toJson());
        written++;
      }
      for (final m in rows('sale_items')) {
        final row = SaleItem.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.saleItems).insert(row);
        await _enqueue('sale_items', row.id, row.toJson());
        written++;
      }
      for (final m in rows('payments')) {
        final row = Payment.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.payments).insert(row);
        await _enqueue('payments', row.id, row.toJson());
        written++;
      }
      for (final m in rows('credit_payments')) {
        final row =
            CreditPayment.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.creditPayments).insert(row);
        await _enqueue('credit_payments', row.id, row.toJson());
        written++;
      }
      for (final m in rows('license_payments')) {
        final row =
            LicensePayment.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.licensePayments).insert(row);
        await _enqueue('license_payments', row.id, row.toJson());
        written++;
      }
      for (final m in rows('expenses')) {
        final row = Expense.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.expenses).insert(row);
        await _enqueue('expenses', row.id, row.toJson());
        written++;
      }
    });
    return written;
  }

  Future<void> _enqueue(
      String table, String rowId, Map<String, dynamic> payload) {
    return _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: table,
          rowId: rowId,
          op: 'upsert',
          payload: jsonEncode(payload),
        ));
  }
}
