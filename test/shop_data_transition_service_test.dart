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
}
