import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'tables.dart';

part 'database.g.dart';

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
    AppSettings,
    Outbox,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  /// For tests: inject an in-memory executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 23;

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
            await m.addColumn(sales, sales.customerPhone);
          }
          // v4: shop display name on license payments.
          if (from < 4) {
            await m.addColumn(licensePayments, licensePayments.shopName);
          }
          // v5: social-order Kanban pipeline.
          if (from < 5) {
            await m.createTable(orders);
            await m.createTable(orderItems);
          }
          // v6: customer payment screenshot on storefront orders.
          if (from < 6) {
            await m.addColumn(orders, orders.paymentProofPath);
          }
          // v7: public product photo URL for the web storefront.
          if (from < 7) {
            await m.addColumn(products, products.imageUrl);
          }
          // v8: delivery tracking (township, carrier, tracking number,
          // delivery status) — carrier-agnostic groundwork.
          if (from < 8) {
            await m.addColumn(orders, orders.township);
            await m.addColumn(orders, orders.deliveryCarrier);
            await m.addColumn(orders, orders.trackingNumber);
            await m.addColumn(orders, orders.deliveryStatus);
          }
          // v9: transfer vs cash-on-delivery, distinct from paymentStatus.
          if (from < 9) {
            await m.addColumn(orders, orders.paymentMethod);
          }
          // v10: refunds — a refund is a normal append-only Sales row
          // pointing back at the sale it reverses.
          if (from < 10) {
            await m.addColumn(sales, sales.refundOfSaleId);
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
            await m.addColumn(sales, sales.customerId);
            await m.addColumn(orders, orders.customerId);
            await m.addColumn(creditPayments, creditPayments.customerId);
          }
          // v13: tiered pricing — a customer's retail/wholesale/vip tier
          // picks which Products price column the Sell screen applies.
          if (from < 13) {
            await m.addColumn(customers, customers.tier);
            await m.addColumn(products, products.wholesalePrice);
            await m.addColumn(products, products.vipPrice);
          }
          // v14: FIFO cost basis. StockLots is local-only (see its doc
          // comment) so it's created fresh here, never migrated from synced
          // data. costSnapshot is null on every pre-existing sale item.
          if (from < 14) {
            await m.createTable(stockLots);
            await m.addColumn(saleItems, saleItems.costSnapshot);
          }
          // v15: flag a storefront order line placed against insufficient
          // stock, so the owner notices before packing it.
          if (from < 15) {
            await m.addColumn(orderItems, orderItems.lowStockAtOrder);
          }
          // v16: owner-set cap on how many units of a product the web
          // storefront may sell, independent of real in-store stock.
          if (from < 16) {
            await m.addColumn(products, products.onlineStockLimit);
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
            await m.addColumn(sales, sales.deviceId);
            await m.createTable(deviceLabels);
          }
          // v19: delivery address, carried over when an Order converts to a
          // Sale — was previously dropped entirely, so a converted order's
          // invoice/receipt had nowhere to deliver it printed on.
          if (from < 19) {
            await m.addColumn(sales, sales.deliveryAddress);
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
            await m.addColumn(recurringExpenses, recurringExpenses.autoGenerate);
            await m.addColumn(
                recurringExpenses, recurringExpenses.generationTiming);
            await m.addColumn(
                recurringExpenses, recurringExpenses.lastGeneratedPeriod);
          }
          // v23: suppliers directory + lightweight purchase-order tracking
          // (what was ordered from whom, at what cost) — receiving a PO
          // reuses the existing restock/adjustStock machinery as-is.
          if (from < 23) {
            await m.createTable(suppliers);
            await m.createTable(purchaseOrders);
            await m.createTable(purchaseOrderItems);
          }
        },
      );

  /// Clears every row of shop-scoped data (every `SyncColumns` table, plus
  /// the local-only `StockLots` FIFO cache) and resets every sync cursor —
  /// used when switching which branch/shop this device is scoped to, since
  /// the local DB isn't partitioned per shop and a stale cursor would skip
  /// any of the new shop's rows older than the old shop's high-water mark.
  /// Callers must ensure the outbox is already empty before calling this —
  /// it does NOT touch the outbox itself, so an unsynced write would
  /// otherwise be silently discarded along with everything else.
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
      await (delete(appSettings)
            ..where((s) => s.key.like('sync.cursor.%')))
          .go();
    });
  }

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'mm_pos.sqlite'));
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
