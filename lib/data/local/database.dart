import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'tables.dart';

part 'database.g.dart';

/// Drift/SQLite migration safeguard for historical/stale local databases where
/// a previous partial migration already added the target column.
bool isDuplicateColumnMigrationError(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('duplicate column name') ||
      msg.contains('duplicate column:') ||
      msg.contains('already exists');
}

@DriftDatabase(
  tables: [
    Categories,
    Products,
    StockLevels,
    StockLots,
    StockMovements,
    Sales,
    SaleItems,
    Payments,
    LicensePayments,
    CreditPayments,
    Orders,
    OrderItems,
    StaffMembers,
    Customers,
    Expenses,
    CashSessions,
    DeviceLabels,
    RecurringExpenses,
    Suppliers,
    PurchaseOrders,
    PurchaseOrderItems,
    PaymentAccounts,
    SupplierPayments,
    EquityEntries,
    AppSettings,
    Outbox,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  /// For tests: inject an in-memory executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 27;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      // v2: credit book — repayments against customer credit.
      if (from < 2) {
        await m.createTable(creditPayments);
      }
      // v3: optional customer phone on sales.
      if (from < 3) {
        await _safeAddColumn(m, sales, sales.customerPhone);
      }
      // v4: shop display name on license payments.
      if (from < 4) {
        await _safeAddColumn(m, licensePayments, licensePayments.shopName);
      }
      // v5: social-order Kanban pipeline.
      if (from < 5) {
        await m.createTable(orders);
        await m.createTable(orderItems);
      }
      // v6: customer payment screenshot on storefront orders.
      if (from < 6) {
        await _safeAddColumn(m, orders, orders.paymentProofPath);
      }
      // v7: public product photo URL for the web storefront.
      if (from < 7) {
        await _safeAddColumn(m, products, products.imageUrl);
      }
      // v8: delivery tracking (township, carrier, tracking number,
      // delivery status) — carrier-agnostic groundwork.
      if (from < 8) {
        await _safeAddColumn(m, orders, orders.township);
        await _safeAddColumn(m, orders, orders.deliveryCarrier);
        await _safeAddColumn(m, orders, orders.trackingNumber);
        await _safeAddColumn(m, orders, orders.deliveryStatus);
      }
      // v9: transfer vs cash-on-delivery, distinct from paymentStatus.
      if (from < 9) {
        await _safeAddColumn(m, orders, orders.paymentMethod);
      }
      // v10: refunds — a refund is a normal append-only Sales row
      // pointing back at the sale it reverses.
      if (from < 10) {
        await _safeAddColumn(m, sales, sales.refundOfSaleId);
      }
      // v11: named staff profiles (so a sale can be attributed to whoever
      // rang it up, not just a shared device PIN).
      if (from < 11) {
        await m.createTable(staffMembers);
      }
      // v12: customer directory — enter a name/phone/address once and
      // reuse it, instead of retyping free text on every invoice/order.
      if (from < 12) {
        await m.createTable(customers);
        await _safeAddColumn(m, sales, sales.customerId);
        await _safeAddColumn(m, orders, orders.customerId);
        await _safeAddColumn(m, creditPayments, creditPayments.customerId);
      }
      // v13: tiered pricing — a customer's retail/wholesale/vip tier
      // picks which Products price column the Sell screen applies.
      if (from < 13) {
        await _safeAddColumn(m, customers, customers.tier);
        await _safeAddColumn(m, products, products.wholesalePrice);
        await _safeAddColumn(m, products, products.vipPrice);
      }
      // v14: FIFO cost basis. StockLots is local-only (see its doc
      // comment) so it's created fresh here, never migrated from synced
      // data. costSnapshot is null on every pre-existing sale item.
      if (from < 14) {
        await m.createTable(stockLots);
        await _safeAddColumn(m, saleItems, saleItems.costSnapshot);
      }
      // v15: flag a storefront order line placed against insufficient
      // stock, so the owner notices before packing it.
      if (from < 15) {
        await _safeAddColumn(m, orderItems, orderItems.lowStockAtOrder);
      }
      // v16: owner-set cap on how many units of a product the web
      // storefront may sell, independent of real in-store stock.
      if (from < 16) {
        await _safeAddColumn(m, products, products.onlineStockLimit);
      }
      // v17: non-inventory operating expenses (rent, utilities, wages,
      // transport, packaging) — separate from restock cost so Analytics
      // never double-counts it against cost-of-goods-sold.
      if (from < 17) {
        await m.createTable(expenses);
      }
      // v18: which physical device rang a sale up, plus owner-editable
      // friendly device names so a raw device UUID can show as
      // something meaningful regardless of which device is viewing it.
      if (from < 18) {
        await _safeAddColumn(m, sales, sales.deviceId);
        await m.createTable(deviceLabels);
      }
      // v19: delivery address, carried over when an Order converts to a
      // Sale — was previously dropped entirely, so a converted order's
      // invoice/receipt had nowhere to deliver it printed on.
      if (from < 19) {
        await _safeAddColumn(m, sales, sales.deliveryAddress);
      }
      // v20: cash-drawer sessions (opening float + closing count, with
      // an expected-cash reconciliation computed from cash sales/
      // repayments/expenses in between).
      if (from < 20) {
        await m.createTable(cashSessions);
      }
      // v21: recurring expense templates (rent, wages, etc.) — quick-fill
      // a new Expense from these each month instead of retyping.
      if (from < 21) {
        await m.createTable(recurringExpenses);
      }
      // v22: optional automatic generation for a recurring expense
      // template, at month-start or month-end, instead of the manual
      // quick-fill this feature originally shipped with.
      if (from < 22) {
        await _safeAddColumn(
          m,
          recurringExpenses,
          recurringExpenses.autoGenerate,
        );
        await _safeAddColumn(
          m,
          recurringExpenses,
          recurringExpenses.generationTiming,
        );
        await _safeAddColumn(
          m,
          recurringExpenses,
          recurringExpenses.lastGeneratedPeriod,
        );
      }
      // v23: suppliers directory + lightweight purchase-order tracking
      // (what was ordered from whom, at what cost) — receiving a PO
      // reuses the existing restock/adjustStock machinery as-is.
      if (from < 23) {
        await m.createTable(suppliers);
        await m.createTable(purchaseOrders);
        await m.createTable(purchaseOrderItems);
      }
      // v24: drop sales.tax — never set/read anywhere (no checkout UI,
      // no receipt/invoice line ever used it); dead weight since it was
      // added. Drift has no dropColumn helper, so this issues the raw
      // SQL directly (supported since SQLite 3.35, well within what the
      // bundled sqlite3 provides).
      if (from < 24) {
        await m.database.customStatement('ALTER TABLE sales DROP COLUMN tax');
      }
      // v25: Payment Accounts — a named-money-account directory (KBZPay,
      // WavePay, or any custom one) with a derived-not-stored running
      // balance; expenses gain an optional accountId so an
      // account-paid expense can reduce that account's balance.
      if (from < 25) {
        await m.createTable(paymentAccounts);
        await _safeAddColumn(m, expenses, expenses.accountId);
      }
      // v26: Accounts Payable (supplier_payments, mirrors credit_payments
      // but for money the shop owes a supplier) + Owner's Equity
      // (equity_entries — contributions/drawings, deliberately separate
      // from expenses so a drawing never affects the P&L).
      if (from < 26) {
        await m.createTable(supplierPayments);
        await m.createTable(equityEntries);
      }
      // v27: surface a permanently-failing outbox row's last error
      // instead of it retrying forever invisibly (see #49's Sync
      // issues screen).
      if (from < 27) {
        await _safeAddColumn(m, outbox, outbox.lastError);
      }
    },
  );

  Future<void> _safeAddColumn(
    Migrator m,
    TableInfo<Table, dynamic> table,
    GeneratedColumn column,
  ) async {
    try {
      await m.addColumn(table, column);
    } catch (error) {
      if (isDuplicateColumnMigrationError(error)) {
        return;
      }
      rethrow;
    }
  }

  /// Clears every row of shop-scoped data (every `SyncColumns` table, plus
  /// the local-only `StockLots` FIFO cache) and resets every sync cursor —
  /// used when switching which branch/shop this device is scoped to, since
  /// the local DB isn't partitioned per shop and a stale cursor would skip
  /// any of the new shop's rows older than the old shop's high-water mark.
  /// Callers must ensure the outbox is already empty before calling this —
  /// it does NOT touch the outbox itself, so an unsynced write would
  /// otherwise be silently discarded along with everything else.
  ///
  /// Cutover note: [fileNameForShop] / [pathForShop] exist so a future
  /// per-shop SQLite swap can replace this wipe. Until that cutover,
  /// production still opens [kLegacyDbFileName] only.
  Future<void> wipeSyncedData() {
    return transaction(() async {
      await delete(categories).go();
      await delete(products).go();
      await delete(stockLevels).go();
      await delete(stockLots).go();
      await delete(stockMovements).go();
      await delete(sales).go();
      await delete(saleItems).go();
      await delete(payments).go();
      await delete(licensePayments).go();
      await delete(creditPayments).go();
      await delete(orders).go();
      await delete(orderItems).go();
      await delete(staffMembers).go();
      await delete(customers).go();
      await delete(expenses).go();
      await delete(cashSessions).go();
      await delete(deviceLabels).go();
      await delete(recurringExpenses).go();
      await delete(suppliers).go();
      await delete(purchaseOrders).go();
      await delete(purchaseOrderItems).go();
      await delete(paymentAccounts).go();
      await delete(supplierPayments).go();
      await delete(equityEntries).go();
      await (delete(
        appSettings,
      )..where((s) => s.key.like('sync.cursor.%'))).go();
      // `staffMembers` (this shop's roster) is wiped above, but which one
      // was "active" is a separate device-local flag (SettingsRepository's
      // `staff.active_id`) that otherwise survives a shop switch and would
      // keep stamping new sales with a staff id from a roster that no
      // longer exists locally (and likely doesn't exist under that id in
      // the new shop either).
      await (delete(
        appSettings,
      )..where((s) => s.key.equals('staff.active_id'))).go();
    });
  }

  /// Legacy single-file DB used by all shops until per-shop cutover.
  static const kLegacyDbFileName = 'mm_pos.sqlite';

  /// When true, [_open] would use [fileNameForShop]. Kept false: wipe path
  /// remains the production branch-switch strategy.
  static const usePerShopDbFiles = false;

  static String sanitizeShopIdForFile(String shopId) =>
      shopId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static String fileNameForShop(String shopId) {
    if (shopId.isEmpty) return kLegacyDbFileName;
    return 'mm_pos_${sanitizeShopIdForFile(shopId)}.sqlite';
  }

  static String pathForShop(String documentsDir, String shopId) =>
      p.join(documentsDir, fileNameForShop(shopId));

  static String legacyDbPath(String documentsDir) =>
      p.join(documentsDir, kLegacyDbFileName);

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = usePerShopDbFiles
          ? fileNameForShop('') // unused until cutover wires active shopId
          : kLegacyDbFileName;
      final file = File(p.join(dir.path, fileName));
      // Work around old Android sqlite; keep tmpdir set for large ops.
      if (Platform.isAndroid) {
        await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
      }
      final cachebase = (await getTemporaryDirectory()).path;
      sqlite3.tempDirectory = cachebase;
      return NativeDatabase.createInBackground(file);
    });
  }
}
