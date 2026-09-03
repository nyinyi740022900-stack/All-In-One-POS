import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/local/database.dart';
import '../../data/local/shop_data_transition_service.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/stock_lots.dart';

/// Import/export of the **active shop's** business data as a single JSON file.
///
/// The backup covers the ledger tables (products, sales, stock, credit, …) but
/// deliberately excludes device-local state — `app_settings` (device id,
/// license cache, printer config — including the device sidecar after
/// per-shop cutover) and the `outbox` — so restoring a backup on the same
/// device never clobbers its identity or pending sync queue.
/// Thrown when a backup file belongs to a different shop than the one that
/// is currently open. Restoring it would delete this shop's rows and insert
/// the other shop's, which every read path then filters out by `shop_id` —
/// leaving the owner staring at an empty shop while the outbox retries
/// forever against a JWT claim that no longer matches. Backup filenames are
/// bare timestamps, so picking the wrong file is easy.
class ShopMismatchException implements Exception {
  const ShopMismatchException({required this.fileShopId});
  final String fileShopId;
  @override
  String toString() => 'shop_mismatch';
}

/// Thrown when this device still has writes that have never reached the
/// cloud. A restore deletes the rows those queued writes point at, and the
/// push loop then drops each orphan as "local row gone" — the sales are
/// gone from the device and never arrive anywhere. Switching branches
/// already refuses for exactly this reason (`assertSafeToClear`); this makes
/// the destructive path here refuse too.
class UnsyncedDataException implements Exception {
  const UnsyncedDataException(this.reason);

  /// `stuck_outbox` or `pending_sync`, matching `assertSafeToClear`.
  final String reason;
  @override
  String toString() => reason;
}

class BackupService {
  BackupService(this._db, this._settings, {this.shopId = '', this.guard});

  final AppDatabase _db;
  final SettingsRepository _settings;
  final String shopId;

  /// Same precheck branch switching uses. Null in contexts that have no
  /// transition service (tests), where the guard is simply skipped.
  final ShopDataTransitionService? guard;

  static const formatVersion = 1;

  /// Every table a restore touches — must stay in sync with [_readAll]'s keys
  /// (and `importReplaceAll`'s delete/insert list). Used to reset that
  /// table's sync cursor after a restore.
  static const _restoredTables = [
    'categories',
    'products',
    'stock_levels',
    'stock_movements',
    'sales',
    'sale_items',
    'payments',
    'credit_payments',
    'license_payments',
    'expenses',
    'orders',
    'order_items',
    'customers',
    'staff_members',
    'staff_permissions',
    'cash_sessions',
    'cash_top_ups',
    'device_labels',
    'recurring_expenses',
    'suppliers',
    'purchase_orders',
    'purchase_order_items',
    'payment_accounts',
    'supplier_payments',
    'equity_entries',
    'shop_profiles',
  ];

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
      'orders':
          (await _db.select(_db.orders).get()).map((r) => r.toJson()).toList(),
      'order_items': (await _db.select(_db.orderItems).get())
          .map((r) => r.toJson())
          .toList(),
      'customers': (await _db.select(_db.customers).get())
          .map((r) => r.toJson())
          .toList(),
      'staff_members': (await _db.select(_db.staffMembers).get())
          .map((r) => r.toJson())
          .toList(),
      'staff_permissions': (await _db.select(_db.staffPermissions).get())
          .map((r) => r.toJson())
          .toList(),
      'cash_sessions': (await _db.select(_db.cashSessions).get())
          .map((r) => r.toJson())
          .toList(),
      'cash_top_ups': (await _db.select(_db.cashTopUps).get())
          .map((r) => r.toJson())
          .toList(),
      'device_labels': (await _db.select(_db.deviceLabels).get())
          .map((r) => r.toJson())
          .toList(),
      'recurring_expenses': (await _db.select(_db.recurringExpenses).get())
          .map((r) => r.toJson())
          .toList(),
      'suppliers': (await _db.select(_db.suppliers).get())
          .map((r) => r.toJson())
          .toList(),
      'purchase_orders': (await _db.select(_db.purchaseOrders).get())
          .map((r) => r.toJson())
          .toList(),
      'purchase_order_items': (await _db.select(_db.purchaseOrderItems).get())
          .map((r) => r.toJson())
          .toList(),
      'payment_accounts': (await _db.select(_db.paymentAccounts).get())
          .map((r) => r.toJson())
          .toList(),
      'supplier_payments': (await _db.select(_db.supplierPayments).get())
          .map((r) => r.toJson())
          .toList(),
      'equity_entries': (await _db.select(_db.equityEntries).get())
          .map((r) => r.toJson())
          .toList(),
      'shop_profiles': (await _db.select(_db.shopProfiles).get())
          .map((r) => r.toJson())
          .toList(),
    };
  }

  /// Serializes the whole business dataset to a pretty JSON string.
  Future<String> exportJson() async {
    final tables = await _readAll();
    final total = tables.values.fold<int>(0, (s, l) => s + l.length);
    final envelope = {
      'app': 'mm_pos',
      // Recorded so a restore can refuse a file from a DIFFERENT shop —
      // the filenames are bare timestamps and give the owner nothing to
      // tell two shops' backups apart.
      'shopId': shopId,
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
  ///
  /// Also resets every restored table's pull cursor. The backup snapshot may
  /// predate the shop's current cloud state (e.g. another device synced
  /// changes after this backup was taken) — without a reset, the next pull's
  /// `since` cursor would still sit at its pre-restore position and silently
  /// skip any remote row not present in the backup file, permanently losing
  /// it locally.
  Future<int> importReplaceAll(String jsonStr) async {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map || decoded['app'] != 'mm_pos') {
      throw const FormatException('Not an MM POS backup file.');
    }
    // Files written before `shopId` was recorded carry no claim about which
    // shop they belong to, so they are allowed through as before — there is
    // nothing to check them against.
    final fileShopId = (decoded['shopId'] as String?) ?? '';
    if (fileShopId.isNotEmpty &&
        shopId.isNotEmpty &&
        fileShopId != shopId) {
      throw ShopMismatchException(fileShopId: fileShopId);
    }
    final blocked = await guard?.assertSafeToClear();
    if (blocked != null) throw UnsyncedDataException(blocked);
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
      await _db.delete(_db.stockLots).go();
      await _db.delete(_db.products).go();
      await _db.delete(_db.categories).go();
      await _db.delete(_db.creditPayments).go();
      await _db.delete(_db.licensePayments).go();
      await _db.delete(_db.expenses).go();
      await _db.delete(_db.orderItems).go();
      await _db.delete(_db.orders).go();
      await _db.delete(_db.customers).go();
      await _db.delete(_db.staffPermissions).go();
      await _db.delete(_db.staffMembers).go();
      await _db.delete(_db.cashTopUps).go();
      await _db.delete(_db.cashSessions).go();
      await _db.delete(_db.deviceLabels).go();
      await _db.delete(_db.recurringExpenses).go();
      await _db.delete(_db.purchaseOrderItems).go();
      await _db.delete(_db.purchaseOrders).go();
      await _db.delete(_db.supplierPayments).go();
      await _db.delete(_db.suppliers).go();
      await _db.delete(_db.paymentAccounts).go();
      await _db.delete(_db.equityEntries).go();
      await _db.delete(_db.shopProfiles).go();

      for (final m in rows('categories')) {
        final row = Category.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.categories).insert(row);
        await _enqueue('categories', row.id);
        written++;
      }
      for (final m in rows('products')) {
        final row = Product.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.products).insert(row);
        await _enqueue('products', row.id);
        written++;
      }
      final seenStockKeys = <String>{};
      for (final m in rows('stock_levels')) {
        // Snapshots taken before schema v33 can contain two rows for one
        // (shop_id, product_id); the unique index now rejects those, which
        // must not fail the whole restore — keep the first, skip extras.
        final key = '${m['shop_id']}|${m['product_id']}';
        if (!seenStockKeys.add(key)) continue;
        final row =
            StockLevel.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.stockLevels).insert(row);
        await _enqueue('stock_levels', row.id);
        written++;
      }
      for (final m in rows('stock_movements')) {
        final row =
            StockMovement.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.stockMovements).insert(row);
        await _enqueue('stock_movements', row.id);
        written++;
      }
      for (final m in rows('sales')) {
        final row = Sale.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.sales).insert(row);
        await _enqueue('sales', row.id);
        written++;
      }
      for (final m in rows('sale_items')) {
        final row = SaleItem.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.saleItems).insert(row);
        await _enqueue('sale_items', row.id);
        written++;
      }
      for (final m in rows('payments')) {
        final row = Payment.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.payments).insert(row);
        await _enqueue('payments', row.id);
        written++;
      }
      for (final m in rows('credit_payments')) {
        final row =
            CreditPayment.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.creditPayments).insert(row);
        await _enqueue('credit_payments', row.id);
        written++;
      }
      for (final m in rows('license_payments')) {
        final row =
            LicensePayment.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.licensePayments).insert(row);
        await _enqueue('license_payments', row.id);
        written++;
      }
      for (final m in rows('expenses')) {
        final row = Expense.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.expenses).insert(row);
        await _enqueue('expenses', row.id);
        written++;
      }
      for (final m in rows('orders')) {
        final row = Order.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.orders).insert(row);
        await _enqueue('orders', row.id);
        written++;
      }
      for (final m in rows('order_items')) {
        final row =
            OrderItem.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.orderItems).insert(row);
        await _enqueue('order_items', row.id);
        written++;
      }
      for (final m in rows('customers')) {
        final row = Customer.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.customers).insert(row);
        await _enqueue('customers', row.id);
        written++;
      }
      for (final m in rows('staff_members')) {
        final row =
            StaffMember.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.staffMembers).insert(row);
        await _enqueue('staff_members', row.id);
        written++;
      }
      for (final m in rows('staff_permissions')) {
        final row =
            StaffPermission.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.staffPermissions).insert(row);
        await _enqueue('staff_permissions', row.id);
        written++;
      }
      for (final m in rows('cash_sessions')) {
        final row =
            CashSession.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.cashSessions).insert(row);
        await _enqueue('cash_sessions', row.id);
        written++;
      }
      for (final m in rows('cash_top_ups')) {
        final row =
            CashTopUp.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.cashTopUps).insert(row);
        await _enqueue('cash_top_ups', row.id);
        written++;
      }
      for (final m in rows('device_labels')) {
        final row =
            DeviceLabel.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.deviceLabels).insert(row);
        await _enqueue('device_labels', row.id);
        written++;
      }
      for (final m in rows('recurring_expenses')) {
        final row =
            RecurringExpense.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.recurringExpenses).insert(row);
        await _enqueue('recurring_expenses', row.id);
        written++;
      }
      for (final m in rows('suppliers')) {
        final row = Supplier.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.suppliers).insert(row);
        await _enqueue('suppliers', row.id);
        written++;
      }
      for (final m in rows('purchase_orders')) {
        final row =
            PurchaseOrder.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.purchaseOrders).insert(row);
        await _enqueue('purchase_orders', row.id);
        written++;
      }
      for (final m in rows('purchase_order_items')) {
        final row = PurchaseOrderItem.fromJson(m)
            .copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.purchaseOrderItems).insert(row);
        await _enqueue('purchase_order_items', row.id);
        written++;
      }
      for (final m in rows('payment_accounts')) {
        final row =
            PaymentAccount.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.paymentAccounts).insert(row);
        await _enqueue('payment_accounts', row.id);
        written++;
      }
      for (final m in rows('supplier_payments')) {
        final row =
            SupplierPayment.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.supplierPayments).insert(row);
        await _enqueue('supplier_payments', row.id);
        written++;
      }
      for (final m in rows('equity_entries')) {
        final row =
            EquityEntry.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.equityEntries).insert(row);
        await _enqueue('equity_entries', row.id);
        written++;
      }
      for (final m in rows('shop_profiles')) {
        final row =
            ShopProfileRow.fromJson(m).copyWith(updatedAt: now, dirty: true);
        await _db.into(_db.shopProfiles).insert(row);
        await _enqueue('shop_profiles', row.id);
        written++;
      }
      final productIds = {
        for (final m in await _db.select(_db.stockMovements).get())
          m.productId,
      };
      for (final id in productIds) {
        await rebuildStockLots(_db, id);
      }
      // Cursor resets belong INSIDE the transaction: they are the whole
      // point of a restore (the next pull must re-fetch everything the
      // snapshot may predate). Clearing them only after the commit left a
      // crash window that reproduced the exact permanent-loss scenario this
      // method exists to prevent. The settings repository shares this
      // database, so the deletes join the same Drift transaction.
      for (final table in _restoredTables) {
        await _settings.clearSyncCursor(table);
      }
    });
    return written;
  }

  Future<void> _enqueue(String table, String rowId) {
    return _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: table,
          rowId: rowId,
          op: 'upsert',
        ));
  }
}
