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
    AppSettings,
    Outbox,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  /// For tests: inject an in-memory executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 20;

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
        },
      );

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
