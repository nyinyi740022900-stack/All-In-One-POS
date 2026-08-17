import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/data/sync/force_apply.dart';
import 'package:mm_pos/data/sync/outbox_constants.dart';
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
  Future<void> markDeleted(
    String table,
    String id,
    DateTime updatedAt, {
    String? shopId,
  }) async {
    final row = store[table]?[id];
    if (row != null) {
      if (shopId != null &&
          shopId.isNotEmpty &&
          row['shop_id'] != null &&
          row['shop_id'] != shopId) {
        return;
      }
      row['is_deleted'] = true;
      row['updated_at'] = updatedAt.toUtc().toIso8601String();
    }
  }

  @override
  Future<ForceApplyResult> forceApply({
    required String table,
    required String op,
    required String id,
    Map<String, dynamic>? row,
    String? onConflict,
  }) async {
    if (op == 'delete') {
      await markDeleted(table, id, DateTime.now(), shopId: row?['shop_id'] as String?);
      return const ForceApplyResult(ForceApplyStatus.applied);
    }
    if (row != null) {
      await upsert(table, row, onConflict: onConflict);
    }
    return const ForceApplyResult(ForceApplyStatus.applied);
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

  @override
  Future<ForceApplyResult> forceApply({
    required String table,
    required String op,
    required String id,
    Map<String, dynamic>? row,
    String? onConflict,
  }) async {
    if (table == failTable) {
      return const ForceApplyResult(ForceApplyStatus.transient, detail: 'boom');
    }
    return super.forceApply(
      table: table,
      op: op,
      id: id,
      row: row,
      onConflict: onConflict,
    );
  }
}

/// Always rejects `upsert` for [failTable] with a genuine (first-time, not
/// pre-seeded) RLS error — models a device whose JWT shop_id claim is
/// currently stale, distinct from `PartialFailRemote`'s generic failure and
/// from the pre-seeded-`lastError` reset tests above (which model a row that
/// *already* failed before this sync, not one failing live during push).
class RlsFailRemote extends FakeSyncRemote {
  RlsFailRemote(this.failTable);
  final String failTable;
  int upsertAttempts = 0;

  @override
  Future<void> upsert(String table, Map<String, dynamic> row,
      {String? onConflict}) async {
    if (table == failTable) {
      upsertAttempts++;
      throw Exception(
        'PostgresException(message: new row violates row-level security '
        'policy for table "$failTable", code: 42501)',
      );
    }
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

  test(
      'payment_accounts RLS failures are reset and succeed on Sync Now '
      '(no Discard required after shop-scoped PK)', () async {
    final now = DateTime.now();
    await db.into(db.paymentAccounts).insert(
          PaymentAccountsCompanion.insert(
            id: 'kbzpay',
            shopId: 'shop-1',
            name: 'KBZPay',
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await db.into(db.outbox).insert(
          OutboxCompanion.insert(
            entityTable: 'payment_accounts',
            rowId: 'kbzpay',
            op: 'upsert',
            payload: '{}',
            attempts: const Value(12),
            lastError: const Value(
              'PostgresException(message: new row violates '
              'row-level security policy for table "payment_accounts", '
              'code: 42501)',
            ),
          ),
        );

    final result = await engine.syncNow();
    expect(result.pushed, greaterThanOrEqualTo(1));
    expect(await db.select(db.outbox).get(), isEmpty);
    expect(
      remote.store['payment_accounts']!['shop-1|kbzpay']!['name'],
      'KBZPay',
    );
  });

  test('any table RLS 42501 outbox row is reset then retried on Sync Now',
      () async {
    final now = DateTime.now();
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat-1',
            shopId: 'shop-1',
            name: 'Drinks',
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await db.into(db.outbox).insert(
          OutboxCompanion.insert(
            entityTable: 'categories',
            rowId: 'cat-1',
            op: 'upsert',
            payload: '{}',
            attempts: const Value(9),
            lastError: const Value(
              'PostgresException(message: new row violates '
              'row-level security policy for table "categories", '
              'code: 42501)',
            ),
          ),
        );

    final result = await engine.syncNow();
    expect(result.pushed, greaterThanOrEqualTo(1));
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test(
      'a live RLS 42501 failure (not pre-seeded) attempts a session-refresh '
      'self-heal exactly once, then records the failure rather than '
      'dropping the row or looping — no live Supabase session in a unit '
      'test, so the refresh itself can\'t succeed here; this only proves '
      'the fallback path stays sound', () async {
    final rlsRemote = RlsFailRemote('categories');
    final rlsEngine = SyncEngine(
        db: db, remote: rlsRemote, settings: settings, shopId: 'shop-1');
    final now = DateTime.now();
    await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            id: 'cat-1',
            shopId: 'shop-1',
            name: 'Drinks',
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await db.into(db.outbox).insert(
          OutboxCompanion.insert(
            entityTable: 'categories',
            rowId: 'cat-1',
            op: 'upsert',
            payload: '{}',
          ),
        );

    await rlsEngine.syncNow();

    // Exactly one real upsert attempt — the refresh-and-retry branch never
    // reaches its own `_pushOne` retry when `refreshSession()` itself throws
    // (no live session in this test), so it isn't double-counted here.
    expect(rlsRemote.upsertAttempts, 1);
    final row = await (db.select(db.outbox)
          ..where((o) => o.entityTable.equals('categories')))
        .getSingle();
    expect(row.attempts, 1);
    expect(row.quarantined, false);
  });

  test(
    'payment_accounts outbox is dropped when remote already has the row',
    () async {
      final now = DateTime.now();
      await db.into(db.paymentAccounts).insert(
            PaymentAccountsCompanion.insert(
              id: 'kbzpay',
              shopId: 'shop-1',
              name: 'KBZPay',
              createdAt: Value(now),
              updatedAt: Value(now),
              dirty: const Value(true),
            ),
          );
      await db.into(db.outbox).insert(
            OutboxCompanion.insert(
              entityTable: 'payment_accounts',
              rowId: 'kbzpay',
              op: 'upsert',
              payload: '{}',
              attempts: const Value(1),
              lastError: const Value(
                'PostgresException(message: new row violates '
                'row-level security policy for table "payment_accounts", '
                'code: 42501)',
              ),
            ),
          );
      remote.store['payment_accounts'] = {
        'shop-1|kbzpay': {
          'id': 'kbzpay',
          'shop_id': 'shop-1',
          'name': 'KBZPay',
          'opening_balance': 0,
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
          'is_deleted': false,
        },
      };

      await engine.syncNow();
      expect(await db.select(db.outbox).get(), isEmpty);
      final local = await (db.select(db.paymentAccounts)
            ..where((t) => t.id.equals('kbzpay')))
          .getSingle();
      expect(local.dirty, isFalse);
    },
  );

  test(
    'categories outbox is dropped when remote already has the row',
    () async {
      final now = DateTime.now();
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'cat-1',
              shopId: 'shop-1',
              name: 'Drinks',
              createdAt: Value(now),
              updatedAt: Value(now),
              dirty: const Value(true),
            ),
          );
      await db.into(db.outbox).insert(
            OutboxCompanion.insert(
              entityTable: 'categories',
              rowId: 'cat-1',
              op: 'upsert',
              payload: '{}',
              attempts: const Value(1),
              lastError: const Value('duplicate key value violates unique constraint'),
            ),
          );
      remote.store['categories'] = {
        'cat-1': {
          'id': 'cat-1',
          'shop_id': 'shop-1',
          'name': 'Drinks',
          'sort': 0,
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
          'is_deleted': false,
        },
      };

      await engine.syncNow();
      expect(await db.select(db.outbox).get(), isEmpty);
      final local = await (db.select(db.categories)
            ..where((t) => t.id.equals('cat-1')))
          .getSingle();
      expect(local.dirty, isFalse);
    },
  );

  test(
    'unknown push failures quarantine after stuck threshold',
    () async {
      final failRemote = PartialFailRemote('products');
      engine = SyncEngine(
        db: db,
        remote: failRemote,
        settings: settings,
        shopId: 'shop-1',
      );
      final now = DateTime.now();
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p-poison',
              shopId: 'shop-1',
              name: 'Poison',
              salePrice: const Value(1),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db.into(db.outbox).insert(
            OutboxCompanion.insert(
              entityTable: 'products',
              rowId: 'p-poison',
              op: 'upsert',
              payload: '{}',
              attempts: Value(kOutboxStuckThreshold - 1),
              lastError: const Value('boom'),
            ),
          );

      await engine.syncNow();
      final rows = await db.select(db.outbox).get();
      expect(rows, hasLength(1));
      expect(rows.single.quarantined, isTrue);
      expect(rows.single.attempts, kOutboxStuckThreshold);

      final active = await (db.select(db.outbox)
            ..where((o) => o.quarantined.equals(false)))
          .get();
      expect(active, isEmpty);
    },
  );

  test(
    'forceApply clears quarantined row without user Discard',
    () async {
      final now = DateTime.now();
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p-held',
              shopId: 'shop-1',
              name: 'Held',
              salePrice: const Value(5),
              createdAt: Value(now),
              updatedAt: Value(now),
              dirty: const Value(true),
            ),
          );
      await db.into(db.outbox).insert(
            OutboxCompanion.insert(
              entityTable: 'products',
              rowId: 'p-held',
              op: 'upsert',
              payload: '{}',
              attempts: Value(kOutboxStuckThreshold),
              lastError: const Value('boom'),
              quarantined: const Value(true),
            ),
          );

      await engine.syncNow();
      expect(await db.select(db.outbox).get(), isEmpty);
      expect(remote.store['products']!['p-held']!['name'], 'Held');
      final local = await (db.select(db.products)
            ..where((t) => t.id.equals('p-held')))
          .getSingle();
      expect(local.dirty, isFalse);
    },
  );
}
