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
    StockMovements,
    Sales,
    SaleItems,
    Payments,
    LicensePayments,
    CreditPayments,
    Orders,
    OrderItems,
    StaffMembers,
    AppSettings,
    Outbox,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  /// For tests: inject an in-memory executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 11;

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
