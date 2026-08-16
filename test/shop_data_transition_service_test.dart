import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/local/shop_data_transition_service.dart';
import 'package:mm_pos/data/sync/outbox_constants.dart';

void main() {
  late AppDatabase db;
  late ShopDataTransitionService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ShopDataTransitionService(db);
  });

  tearDown(() async => db.close());

  test('precheck reports pending and stuck outbox rows', () async {
    for (var i = 0; i < 3; i++) {
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              entityTable: 'products',
              rowId: 'row-$i',
              op: 'upsert',
              payload: '{}',
              attempts: Value(i == 2 ? kOutboxStuckThreshold : 0),
            ),
          );
    }

    final info = await service.precheck();
    expect(info.pendingOutboxCount, 3);
    expect(info.stuckOutboxCount, 1);
  });

  test('assertSafeToClear blocks on stuck writes first', () async {
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            entityTable: 'products',
            rowId: 'stuck-1',
            op: 'upsert',
            payload: '{}',
            attempts: Value(kOutboxStuckThreshold),
          ),
        );
    expect(await service.assertSafeToClear(), 'stuck_outbox');
  });

  test('assertSafeToClear blocks on pending writes', () async {
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            entityTable: 'products',
            rowId: 'pending-1',
            op: 'upsert',
            payload: '{}',
          ),
        );
    expect(await service.assertSafeToClear(), 'pending_sync');
  });

  test('assertSafeToClear allows empty outbox', () async {
    expect(await service.assertSafeToClear(), isNull);
  });

  test(
    'prepareShopSwitch skips wipe when usePerShopDbFiles (reports target file)',
    () async {
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c1',
              shopId: 'shop-a',
              name: 'Keep',
              updatedAt: Value(DateTime.now()),
            ),
          );
      final prep = await service.prepareShopSwitch(
        fromShopId: 'shop-a',
        toShopId: 'shop-b',
      );
      expect(prep.fromShopId, 'shop-a');
      expect(prep.toShopId, 'shop-b');
      expect(prep.targetDbFileName, 'mm_pos_shop-b.sqlite');
      expect(prep.usedWipeFallback, isFalse);
      expect(AppDatabase.usePerShopDbFiles, isTrue);
      // Shared in-memory DB is not wiped — reopen path owns isolation.
      final cats = await db.select(db.categories).get();
      expect(cats, isNotEmpty);
    },
  );

  group('promoteShopIdentity', () {
    const from = 'free-device1';
    const to = 'shop-real1';

    Future<void> seed() async {
      await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: 'c1',
              shopId: from,
              name: 'Drinks',
              updatedAt: Value(DateTime.now()),
            ),
          );
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p1',
              shopId: from,
              name: 'Cola',
              updatedAt: Value(DateTime.now()),
            ),
          );
      // A deleted row: still gets its shop_id rewritten (so nothing is
      // orphaned under the old id if it's ever undeleted/reconciled), but
      // an outbox backfill for a tombstone is pointless — the sync engine
      // already handles is_deleted rows via the normal dirty-row path if
      // they're ever touched again, and re-pushing a delete on every
      // promotion would be pure waste.
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'p2-deleted',
              shopId: from,
              name: 'Discontinued',
              isDeleted: const Value(true),
              updatedAt: Value(DateTime.now()),
            ),
          );
      await db
          .into(db.appSettings)
          .insert(AppSettingsCompanion.insert(key: 'shop.name.$from', value: 'Test Shop'));
      // id == shopId for this table (one row per shop) — a different shape
      // from every other table above, where only shopId moves.
      await db.into(db.shopProfiles).insert(
            ShopProfilesCompanion.insert(
              id: from,
              shopId: from,
              name: 'Test Shop',
              updatedAt: Value(DateTime.now()),
            ),
          );
    }

    test('rewrites shop_id across tables and rekeys shop-scoped settings',
        () async {
      await seed();
      await service.promoteShopIdentity(fromShopId: from, toShopId: to);

      final cats = await db.select(db.categories).get();
      expect(cats.single.shopId, to);
      final products = await db.select(db.products).get();
      expect(products.every((p) => p.shopId == to), isTrue);

      final settingsRow = await (db.select(db.appSettings)
            ..where((s) => s.key.equals('shop.name.$to')))
          .getSingleOrNull();
      expect(settingsRow?.value, 'Test Shop');
      final staleKey = await (db.select(db.appSettings)
            ..where((s) => s.key.equals('shop.name.$from')))
          .getSingleOrNull();
      expect(staleKey, isNull);
    });

    test('enqueues an outbox upsert per surviving row, not deleted ones',
        () async {
      await seed();
      await service.promoteShopIdentity(fromShopId: from, toShopId: to);

      final outbox = await db.select(db.outbox).get();
      final categoryRows = outbox.where((o) => o.entityTable == 'categories');
      final productRows = outbox.where((o) => o.entityTable == 'products');
      expect(categoryRows.map((o) => o.rowId), ['c1']);
      // p2-deleted is excluded — see the comment in seed().
      expect(productRows.map((o) => o.rowId), ['p1']);
    });

    test('rekeys shop_profiles\' id together with shopId, not just shopId '
        '(the one table where id == shopId)', () async {
      await seed();
      await service.promoteShopIdentity(fromShopId: from, toShopId: to);

      final rows = await db.select(db.shopProfiles).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, to);
      expect(rows.single.shopId, to);

      final outbox = await db.select(db.outbox).get();
      final profileRows = outbox.where((o) => o.entityTable == 'shop_profiles');
      expect(profileRows.map((o) => o.rowId), [to]);
    });

    test('is idempotent — re-running after an already-promoted shop is a '
        'safe no-op (this is exactly what a crash-recovery resume relies on)',
        () async {
      await seed();
      await service.promoteShopIdentity(fromShopId: from, toShopId: to);
      final outboxCountAfterFirst = (await db.select(db.outbox).get()).length;

      await service.promoteShopIdentity(fromShopId: from, toShopId: to);
      final rows = await db.select(db.categories).get();
      expect(rows.single.shopId, to); // unchanged, still correct
      final outboxCountAfterSecond = (await db.select(db.outbox).get()).length;
      // No new rows moved on the second pass, so no new backfill either.
      expect(outboxCountAfterSecond, outboxCountAfterFirst);
    });

    test('does nothing for an empty or identical shop id', () async {
      await seed();
      await service.promoteShopIdentity(fromShopId: from, toShopId: from);
      await service.promoteShopIdentity(fromShopId: '', toShopId: to);

      final cats = await db.select(db.categories).get();
      expect(cats.single.shopId, from);
      final outbox = await db.select(db.outbox).get();
      expect(outbox, isEmpty);
    });
  });
}
