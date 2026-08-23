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
  Future<void> upsert(
    String table,
    Map<String, dynamic> row, {
    String? onConflict,
  }) async {
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
    String? hlc,
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
      if (hlc != null) row['hlc'] = hlc;
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
      await markDeleted(
        table,
        id,
        DateTime.now(),
        shopId: row?['shop_id'] as String?,
      );
      return const ForceApplyResult(ForceApplyStatus.applied);
    }
    if (row != null) {
      await upsert(table, row, onConflict: onConflict);
    }
    return const ForceApplyResult(ForceApplyStatus.applied);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(
    String table,
    String shopId,
    DateTime? since,
  ) async {
    // Server-stamped `received_at` semantics (migration 0064): the engine
    // cursors on received_at; the fake derives it from updated_at when the
    // pusher (toRemote payloads) didn't supply one — mirroring how the real
    // trigger stamps rows server-side.
    DateTime receivedOf(Map<String, dynamic> r) =>
        DateTime.parse((r['received_at'] ?? r['updated_at']) as String);
    final rows =
        (store[table] ?? {}).values
            .where(
              (r) =>
                  r['shop_id'] == shopId &&
                  (since == null || !receivedOf(r).isBefore(since)),
            )
            .map(
              (e) =>
                  Map<String, dynamic>.from(e)
                    ..['received_at'] ??= e['updated_at'],
            )
            .toList()
          ..sort((a, b) => receivedOf(a).compareTo(receivedOf(b)));
    return rows;
  }

  @override
  Future<Map<String, ({String updatedAt, String? hlc})>?> fetchRowStampsByIds(
    String table,
    String shopId,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    return {
      for (final r in (store[table] ?? {}).values)
        if (r['shop_id'] == shopId && ids.contains(r['id']))
          r['id'] as String: (
            updatedAt: r['updated_at'] as String,
            hlc: r['hlc'] as String?,
          ),
    };
  }
}

/// Fails to upsert one specific table, to prove the outbox isolates failures.
class PartialFailRemote extends FakeSyncRemote {
  PartialFailRemote(this.failTable);
  final String failTable;

  @override
  Future<void> upsert(
    String table,
    Map<String, dynamic> row, {
    String? onConflict,
  }) async {
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
  Future<void> upsert(
    String table,
    Map<String, dynamic> row, {
    String? onConflict,
  }) async {
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

/// Delegates everything to an inner fake but makes every `fetchChanges`
/// throw — models a network blip during reconcile's remote timestamp probe,
/// proving pending edits survive and the normal push path still runs.
class FlakyFetchRemote implements SyncRemote {
  FlakyFetchRemote(this.inner);
  final FakeSyncRemote inner;
  Map<String, Map<String, Map<String, dynamic>>> get store => inner.store;

  @override
  Future<Map<String, ({String updatedAt, String? hlc})>?> fetchRowStampsByIds(
    String table,
    String shopId,
    Set<String> ids,
  ) => inner.fetchRowStampsByIds(table, shopId, ids);

  @override
  Future<void> upsert(
    String table,
    Map<String, dynamic> row, {
    String? onConflict,
  }) => inner.upsert(table, row, onConflict: onConflict);

  @override
  Future<void> markDeleted(
    String table,
    String id,
    DateTime updatedAt, {
    String? shopId,
    String? hlc,
  }) => inner.markDeleted(table, id, updatedAt, shopId: shopId, hlc: hlc);

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(
    String table,
    String shopId,
    DateTime? since,
  ) async {
    throw Exception('network blip');
  }

  @override
  Future<ForceApplyResult> forceApply({
    required String table,
    required String op,
    required String id,
    Map<String, dynamic>? row,
    String? onConflict,
  }) => inner.forceApply(
    table: table,
    op: op,
    id: id,
    row: row,
    onConflict: onConflict,
  );
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
      db: db,
      remote: remote,
      settings: settings,
      shopId: 'shop-1',
    );
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

  test(
    'a multi-row pull re-fires watching streams ONCE, not once per row '
    '(audit C1 — a sync drain must not rebuild the Sell grid mid-task)',
    () async {
      final now = DateTime.now();
      remote.store['products'] = {
        for (var i = 0; i < 5; i++)
          'p$i': remoteProduct('p$i', name: 'Item $i', updatedAt: now),
      };

      var emissions = 0;
      final sub = inventory.watchProducts().listen((_) => emissions++);
      await pumpEventQueue(); // let the initial emission land
      final before = emissions;

      await engine.syncNow();
      await pumpEventQueue(); // post-commit stream dispatch is async

      // The whole page applies in ONE transaction, so Drift dispatches one
      // products-table update at commit. Before batching this was one
      // invalidation PER ROW (5 here, 500 on a full page) — every one of them
      // rebuilt Sell/Inventory/Analytics while the cashier worked.
      expect(emissions - before, 1);
      await sub.cancel();
    },
  );

  test(
    'last-write-wins: newer local edit is not overwritten by older remote',
    () async {
      // Local product created now.
      final id = await inventory.upsertProduct(
        name: 'Local name',
        salePrice: 100,
      );
      // Older remote version of the same id.
      remote.store['products'] = {
        id: remoteProduct(
          id,
          name: 'Old remote name',
          updatedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      };

      await engine.syncNow();

      final local = (await inventory.watchProducts().first).single;
      expect(local.product.name, 'Local name');
    },
  );

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

  test('a row stamped BELOW the cursor (commit-order race: an older '
      'transaction committing after a newer one advanced the watermark) is '
      'still applied thanks to the pull overlap window, not silently '
      'dropped', () async {
    final t0 = DateTime.now().toUtc();
    remote.store['products'] = {
      'p1': remoteProduct('p1', name: 'First', updatedAt: t0),
    };
    await engine.syncNow();

    // A slow transaction commits afterwards but carries an EARLIER
    // received_at — under the old client-clock watermark it would never be
    // fetched again; the 2-minute rewind re-fetches and applies it.
    remote.store['products']!['p2'] = remoteProduct(
      'p2',
      name: 'Late commit',
      updatedAt: t0.subtract(const Duration(seconds: 30)),
    );

    final second = await engine.syncNow();
    // Below-cursor applications aren't counted as fresh pulls (see _pull).
    expect(second.pulled, 0);
    final local = await inventory.watchProducts().first;
    expect(
      local.map((p) => p.product.name),
      containsAll(['First', 'Late commit']),
    );
  });

  test('a failing row does not block later outbox items', () async {
    // A product (whose push we will force to fail) …
    await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 10);
    // … and a license payment queued behind it that must still reach the server.
    await db
        .into(db.licensePayments)
        .insert(
          LicensePaymentsCompanion.insert(
            id: 'lp1',
            shopId: 'shop-1',
            licenseKey: 'DEMO',
            method: 'kbzpay',
            amount: 10000,
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            entityTable: 'license_payments',
            rowId: 'lp1',
            op: 'upsert',
          ),
        );

    final failing = PartialFailRemote('products');
    final engine2 = SyncEngine(
      db: db,
      remote: failing,
      settings: settings,
      shopId: 'shop-1',
    );
    await engine2.syncNow();

    // The payment got through despite the product push failing.
    expect(failing.store['license_payments']?['lp1'], isNotNull);
    // The failed product row stays queued; the payment row was removed.
    final remaining = await db.select(db.outbox).get();
    expect(remaining.any((o) => o.entityTable == 'products'), isTrue);
    expect(remaining.any((o) => o.entityTable == 'license_payments'), isFalse);
  });

  test(
    'a failing row records the exception in lastError and bumps attempts',
    () async {
      await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 10);

      final failing = PartialFailRemote('products');
      final engine2 = SyncEngine(
        db: db,
        remote: failing,
        settings: settings,
        shopId: 'shop-1',
      );
      await engine2.syncNow();
      await engine2.syncNow();

      final row = (await db.select(db.outbox).get()).singleWhere(
        (o) => o.entityTable == 'products',
      );
      expect(row.attempts, 2);
      expect(row.lastError, contains('boom'));
    },
  );

  test('delete is pushed as a tombstone', () async {
    final id = await inventory.upsertProduct(name: 'Temp', salePrice: 1);
    await engine.syncNow(); // push create
    await inventory.deleteProduct(id);
    await engine.syncNow(); // push delete

    expect(remote.store['products']![id]!['is_deleted'], true);
  });

  test('payment_accounts RLS failures are reset and succeed on Sync Now '
      '(no Discard required after shop-scoped PK)', () async {
    final now = DateTime.now();
    await db
        .into(db.paymentAccounts)
        .insert(
          PaymentAccountsCompanion.insert(
            id: 'kbzpay',
            shopId: 'shop-1',
            name: 'KBZPay',
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            entityTable: 'payment_accounts',
            rowId: 'kbzpay',
            op: 'upsert',
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

  test(
    'any table RLS 42501 outbox row is reset then retried on Sync Now',
    () async {
      final now = DateTime.now();
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'cat-1',
              shopId: 'shop-1',
              name: 'Drinks',
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              entityTable: 'categories',
              rowId: 'cat-1',
              op: 'upsert',
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
    },
  );

  test('a live RLS 42501 failure (not pre-seeded) attempts a session-refresh '
      'self-heal exactly once, then records the failure rather than '
      'dropping the row or looping — no live Supabase session in a unit '
      'test, so the refresh itself can\'t succeed here; this only proves '
      'the fallback path stays sound', () async {
    final rlsRemote = RlsFailRemote('categories');
    final rlsEngine = SyncEngine(
      db: db,
      remote: rlsRemote,
      settings: settings,
      shopId: 'shop-1',
    );
    final now = DateTime.now();
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'cat-1',
            shopId: 'shop-1',
            name: 'Drinks',
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            entityTable: 'categories',
            rowId: 'cat-1',
            op: 'upsert',
          ),
        );

    await rlsEngine.syncNow();

    // Exactly one real upsert attempt — the refresh-and-retry branch never
    // reaches its own `_pushOne` retry when `refreshSession()` itself throws
    // (no live session in this test), so it isn't double-counted here.
    expect(rlsRemote.upsertAttempts, 1);
    final row = await (db.select(
      db.outbox,
    )..where((o) => o.entityTable.equals('categories'))).getSingle();
    expect(row.attempts, 1);
    expect(row.quarantined, false);
  });

  test('payment_accounts duplicate outbox (same content/timestamp as remote) '
      'is re-pushed idempotently and cleared — never dropped blind', () async {
    final now = DateTime.now();
    await db
        .into(db.paymentAccounts)
        .insert(
          PaymentAccountsCompanion.insert(
            id: 'kbzpay',
            shopId: 'shop-1',
            name: 'KBZPay',
            createdAt: Value(now),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            entityTable: 'payment_accounts',
            rowId: 'kbzpay',
            op: 'upsert',
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
    final local = await (db.select(
      db.paymentAccounts,
    )..where((t) => t.id.equals('kbzpay'))).getSingle();
    expect(local.dirty, isFalse);
  });

  test('categories duplicate outbox (same content/timestamp as remote) is '
      're-pushed idempotently and cleared — never dropped blind', () async {
    final now = DateTime.now();
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'cat-1',
            shopId: 'shop-1',
            name: 'Drinks',
            createdAt: Value(now),
            updatedAt: Value(now),
            dirty: const Value(true),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            entityTable: 'categories',
            rowId: 'cat-1',
            op: 'upsert',
            attempts: const Value(1),
            lastError: const Value(
              'duplicate key value violates unique constraint',
            ),
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
    final local = await (db.select(
      db.categories,
    )..where((t) => t.id.equals('cat-1'))).getSingle();
    expect(local.dirty, isFalse);
  });

  test('unknown push failures quarantine after stuck threshold', () async {
    final failRemote = PartialFailRemote('products');
    engine = SyncEngine(
      db: db,
      remote: failRemote,
      settings: settings,
      shopId: 'shop-1',
    );
    final now = DateTime.now();
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p-poison',
            shopId: 'shop-1',
            name: 'Poison',
            salePrice: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            entityTable: 'products',
            rowId: 'p-poison',
            op: 'upsert',
            attempts: Value(kOutboxStuckThreshold - 1),
            lastError: const Value('boom'),
          ),
        );

    await engine.syncNow();
    final rows = await db.select(db.outbox).get();
    expect(rows, hasLength(1));
    expect(rows.single.quarantined, isTrue);
    expect(rows.single.attempts, kOutboxStuckThreshold);

    final active = await (db.select(
      db.outbox,
    )..where((o) => o.quarantined.equals(false))).get();
    expect(active, isEmpty);
  });

  test('an offline edit to an already-synced row is PUSHED, not dropped '
      '(regression: reconcile used to drop any pending upsert whose id '
      'existed remotely, silently losing every mutable-row edit)', () async {
    // Create + push, so the remote now holds this row's id.
    final id = await inventory.upsertProduct(name: 'Original', salePrice: 100);
    await engine.syncNow();
    expect(remote.store['products']![id]!['name'], 'Original');
    expect(await db.select(db.outbox).get(), isEmpty);

    // Offline edit: newer updatedAt + a fresh pending outbox upsert.
    await inventory.upsertProduct(id: id, name: 'Renamed', salePrice: 200);
    await engine.syncNow();

    // The edit must reach the server — the id existing remotely from the
    // creation push is not a reason to drop it.
    expect(remote.store['products']![id]!['name'], 'Renamed');
    expect(remote.store['products']![id]!['sale_price'], 200);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test(
    'a pending edit OLDER than the remote row is dropped and the pull '
    'converges to the remote copy (the only case reconcile may drop)',
    () async {
      // Created locally but never pushed; local updatedAt = now.
      final id = await inventory.upsertProduct(
        name: 'Local stale',
        salePrice: 100,
      );

      // Another device edited the same row afterwards (strictly newer).
      final newer = DateTime.now().add(const Duration(minutes: 5));
      remote.store['products'] = {
        id: remoteProduct(id, name: 'Remote newer', updatedAt: newer),
      };

      await engine.syncNow();

      // Outbox dropped (remote strictly newer) and the pull applied it.
      expect(await db.select(db.outbox).get(), isEmpty);
      final local = await (db.select(
        db.products,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(local.name, 'Remote newer');
      expect(local.dirty, isFalse);
    },
  );

  test('when the remote fetch fails during reconcile, pending edits are kept '
      'and still pushed by the normal push path', () async {
    final id = await inventory.upsertProduct(name: 'Original', salePrice: 100);
    await engine.syncNow();
    await inventory.upsertProduct(id: id, name: 'Renamed', salePrice: 200);

    // A remote that accepts pushes but fails every fetchChanges (so
    // reconcile can't compare timestamps) — push must still succeed.
    final flaky = FlakyFetchRemote(remote);
    final flakyEngine = SyncEngine(
      db: db,
      remote: flaky,
      settings: settings,
      shopId: 'shop-1',
    );
    // Push succeeds; the trailing pull then fails on the blip and surfaces
    // as a thrown error (SyncController catches it in production). The
    // assertions below prove the edit was pushed before that point.
    try {
      await flakyEngine.syncNow();
    } catch (_) {}

    expect(flaky.store['products']![id]!['name'], 'Renamed');
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('LWW tie with a CLEAN local copy converges to the remote row '
      '(audit M4 — same-second edits must not split-brain)', () async {
    // Whole seconds — Drift stores DateTimes truncated to second precision,
    // so both sides must be compared in that domain.
    final t = DateTime.fromMillisecondsSinceEpoch(
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
    );
    // Local copy that is already reflected in the cloud (clean), stamped T.
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: 'p-tie',
            shopId: 'shop-1',
            name: 'Version A',
            salePrice: const Value(100),
            createdAt: Value(t),
            updatedAt: Value(t),
            dirty: const Value(false),
          ),
        );
    // Remote holds the other device's equal-stamped version (it pushed
    // physically later, so the server kept ITS content).
    remote.store['products'] = {
      'p-tie': remoteProduct('p-tie', name: 'Version B', updatedAt: t),
    };

    await engine.syncNow();

    final local = await (db.select(
      db.products,
    )..where((t2) => t2.id.equals('p-tie'))).getSingle();
    expect(
      local.name,
      'Version B',
      reason: 'a clean local copy defers to the server on exact ties',
    );
  });

  test(
    'LWW tie with a DIRTY (unsynced) local edit keeps the local edit',
    () async {
      final t = DateTime.fromMillisecondsSinceEpoch(
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
      );
      await inventory.upsertProduct(
        id: 'p-tie2',
        name: 'My Edit',
        salePrice: 1,
      );
      // Force the local stamp to exactly equal the incoming remote stamp.
      await (db.update(db.products)..where((t2) => t2.id.equals('p-tie2')))
          .write(ProductsCompanion(updatedAt: Value(t)));
      remote.store['products'] = {
        'p-tie2': remoteProduct('p-tie2', name: 'Other Device', updatedAt: t),
      };

      await engine.syncNow();

      final local = await (db.select(
        db.products,
      )..where((t2) => t2.id.equals('p-tie2'))).getSingle();
      expect(
        local.name,
        'My Edit',
        reason: 'an unsynced edit always wins its own timestamp tie',
      );
    },
  );

  test('forceApply clears quarantined row without user Discard', () async {
    final now = DateTime.now();
    await db
        .into(db.products)
        .insert(
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
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            entityTable: 'products',
            rowId: 'p-held',
            op: 'upsert',
            attempts: Value(kOutboxStuckThreshold),
            lastError: const Value('boom'),
            quarantined: const Value(true),
          ),
        );

    await engine.syncNow();
    expect(await db.select(db.outbox).get(), isEmpty);
    expect(remote.store['products']!['p-held']!['name'], 'Held');
    final local = await (db.select(
      db.products,
    )..where((t) => t.id.equals('p-held'))).getSingle();
    expect(local.dirty, isFalse);
  });
}
