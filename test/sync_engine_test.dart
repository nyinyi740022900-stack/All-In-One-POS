import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/data/sync/sync_engine.dart';

/// In-memory fake backend: store[table][id] = row map.
class FakeSyncRemote implements SyncRemote {
  final Map<String, Map<String, Map<String, dynamic>>> store = {};

  @override
  Future<void> upsert(String table, Map<String, dynamic> row,
      {String? onConflict}) async {
    final key = onConflict == 'shop_id,id'
        ? '${row['shop_id']}|${row['id']}'
        : row['id'] as String;
    (store[table] ??= {})[key] = Map.of(row);
  }

  @override
  Future<void> markDeleted(String table, String id, DateTime updatedAt) async {
    final row = store[table]?[id];
    if (row != null) {
      row['is_deleted'] = true;
      row['updated_at'] = updatedAt.toUtc().toIso8601String();
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(
      String table, String shopId, DateTime? since) async {
    // Inclusive (>=), matching SupabaseSyncRemote's `gte` filter — see its
    // doc comment for why the pull filter can't be a strict `gt`.
    final rows = (store[table] ?? {})
        .values
        .where((r) =>
            r['shop_id'] == shopId &&
            (since == null ||
                !DateTime.parse(r['updated_at'] as String).isBefore(since)))
        .map((e) => Map<String, dynamic>.from(e))
        .toList()
      ..sort((a, b) => DateTime.parse(a['updated_at'] as String)
          .compareTo(DateTime.parse(b['updated_at'] as String)));
    return rows;
  }
}

/// Fails to upsert one specific table, to prove the outbox isolates failures.
class PartialFailRemote extends FakeSyncRemote {
  PartialFailRemote(this.failTable);
  final String failTable;

  @override
  Future<void> upsert(String table, Map<String, dynamic> row,
      {String? onConflict}) async {
    if (table == failTable) throw Exception('boom');
    return super.upsert(table, row, onConflict: onConflict);
  }
}

Map<String, dynamic> remoteProduct(
  String id, {
  String shop = 'shop-1',
  String name = 'Remote item',
  int price = 500,
  required DateTime updatedAt,
  bool deleted = false,
}) {
  final iso = updatedAt.toUtc().toIso8601String();
  return {
    'id': id,
    'shop_id': shop,
    'name': name,
    'sku': null,
    'barcode': null,
    'category_id': null,
    'cost_price': 0,
    'sale_price': price,
    'unit': 'pcs',
    'image_path': null,
    'is_active': true,
    'created_at': iso,
    'updated_at': iso,
    'is_deleted': deleted,
  };
}

void main() {
  late AppDatabase db;
  late InventoryRepository inventory;
  late SettingsRepository settings;
  late FakeSyncRemote remote;
  late SyncEngine engine;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    inventory = InventoryRepository(db, 'shop-1');
    settings = SettingsRepository(db);
    remote = FakeSyncRemote();
    engine = SyncEngine(
        db: db, remote: remote, settings: settings, shopId: 'shop-1');
  });

  tearDown(() async => db.close());

  test('push drains outbox and uploads product + stock rows', () async {
    await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 10);

    final result = await engine.syncNow();

    expect(result.pushed, greaterThanOrEqualTo(2));
    expect(remote.store['products'], isNotNull);
    expect(remote.store['products']!.values.single['name'], 'Coke');
    expect(remote.store['stock_levels']!.values.single['quantity'], 10);

    // Outbox emptied.
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('pull inserts new remote rows locally', () async {
    remote.store['products'] = {
      'p1': remoteProduct('p1', name: 'From cloud', updatedAt: DateTime.now()),
    };

    await engine.syncNow();

    final local = await inventory.watchProducts().first;
    expect(local.map((p) => p.product.name), contains('From cloud'));
  });

  test('last-write-wins: newer local edit is not overwritten by older remote',
      () async {
    // Local product created now.
    final id =
        await inventory.upsertProduct(name: 'Local name', salePrice: 100);
    // Older remote version of the same id.
    remote.store['products'] = {
      id: remoteProduct(id,
          name: 'Old remote name',
          updatedAt: DateTime.now().subtract(const Duration(days: 1))),
    };

    await engine.syncNow();

    final local = (await inventory.watchProducts().first).single;
    expect(local.product.name, 'Local name');
  });

  test('pull cursor advances so unchanged rows are not re-pulled', () async {
    remote.store['products'] = {
      'p1': remoteProduct('p1', updatedAt: DateTime.now()),
    };
    final first = await engine.syncNow();
    expect(first.pulled, greaterThanOrEqualTo(1));

    // Nothing changed remotely -> second sync pulls zero.
    final second = await engine.syncNow();
    expect(second.pulled, 0);
  });

  test(
      'a second row landing at the exact same updated_at as the cursor is '
      'still picked up on the next pull, not silently dropped', () async {
    // Same instant: Drift's DateTimeColumn truncates to whole seconds, so
    // two changes within the same second are indistinguishable — a strict
    // `gt` cursor filter would permanently drop whichever one lands here.
    final tiedInstant = DateTime.now();
    remote.store['products'] = {
      'p1': remoteProduct('p1', name: 'First', updatedAt: tiedInstant),
    };
    final first = await engine.syncNow();
    expect(first.pulled, greaterThanOrEqualTo(1));

    // A second row appears later in wall time but happens to round to the
    // exact same `updated_at` the cursor now sits on.
    remote.store['products']!['p2'] =
        remoteProduct('p2', name: 'Second', updatedAt: tiedInstant);
    final second = await engine.syncNow();
    expect(second.pulled, 1);

    final local = await inventory.watchProducts().first;
    expect(local.map((p) => p.product.name), containsAll(['First', 'Second']));

    // A third sync with nothing new doesn't re-pull either tied row again.
    final third = await engine.syncNow();
    expect(third.pulled, 0);
  });

  test('a failing row does not block later outbox items', () async {
    // A product (whose push we will force to fail) …
    await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 10);
    // … and a license payment queued behind it that must still reach the server.
    await db.into(db.licensePayments).insert(LicensePaymentsCompanion.insert(
          id: 'lp1',
          shopId: 'shop-1',
          licenseKey: 'DEMO',
          method: 'kbzpay',
          amount: 10000,
        ));
    await db.into(db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'license_payments',
          rowId: 'lp1',
          op: 'upsert',
          payload: '{}',
        ));

    final failing = PartialFailRemote('products');
    final engine2 = SyncEngine(
        db: db, remote: failing, settings: settings, shopId: 'shop-1');
    await engine2.syncNow();

    // The payment got through despite the product push failing.
    expect(failing.store['license_payments']?['lp1'], isNotNull);
    // The failed product row stays queued; the payment row was removed.
    final remaining = await db.select(db.outbox).get();
    expect(remaining.any((o) => o.entityTable == 'products'), isTrue);
    expect(remaining.any((o) => o.entityTable == 'license_payments'), isFalse);
  });

  test('a failing row records the exception in lastError and bumps attempts',
      () async {
    await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 10);

    final failing = PartialFailRemote('products');
    final engine2 = SyncEngine(
        db: db, remote: failing, settings: settings, shopId: 'shop-1');
    await engine2.syncNow();
    await engine2.syncNow();

    final row = (await db.select(db.outbox).get())
        .singleWhere((o) => o.entityTable == 'products');
    expect(row.attempts, 2);
    expect(row.lastError, contains('boom'));
  });

  test('delete is pushed as a tombstone', () async {
    final id = await inventory.upsertProduct(name: 'Temp', salePrice: 1);
    await engine.syncNow(); // push create
    await inventory.deleteProduct(id);
    await engine.syncNow(); // push delete

    expect(remote.store['products']![id]!['is_deleted'], true);
  });
}
