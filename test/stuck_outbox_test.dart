import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/local/shop_data_transition_service.dart';
import 'package:mm_pos/data/sync/outbox_constants.dart';
import 'package:mm_pos/data/sync/sync_providers.dart';

/// Poison outbox rows are quarantined (not Discard'd) so branch switch is
/// never blocked — see SyncEngine quarantine + Sync Issues Support path.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> insertOutboxRow({
    int attempts = 0,
    String? lastError,
    bool quarantined = false,
  }) async {
    return db.into(db.outbox).insert(
          OutboxCompanion.insert(
            entityTable: 'products',
            rowId: 'p1',
            op: 'upsert',
            payload: '{}',
            attempts: Value(attempts),
            lastError: Value(lastError),
            quarantined: Value(quarantined),
          ),
        );
  }

  test('a row below the stuck threshold does not appear', () async {
    await insertOutboxRow(attempts: kOutboxStuckThreshold - 1);
    final rows = await container.read(stuckOutboxProvider.future);
    expect(rows, isEmpty);
  });

  test(
    'a non-quarantined row at the stuck threshold appears',
    () async {
      await insertOutboxRow(attempts: kOutboxStuckThreshold, lastError: 'boom');
      final rows = await container.read(stuckOutboxProvider.future);
      expect(rows, hasLength(1));
      expect(rows.single.lastError, 'boom');
    },
  );

  test('quarantined rows are excluded from stuck and pending counts', () async {
    await insertOutboxRow(
      attempts: kOutboxStuckThreshold,
      lastError: 'boom',
      quarantined: true,
    );
    await insertOutboxRow(attempts: 0);

    final stuck = await container.read(stuckOutboxProvider.future);
    expect(stuck, isEmpty);

    final quarantined = await container.read(quarantinedOutboxProvider.future);
    expect(quarantined, hasLength(1));

    final pending = await container.read(pendingOutboxRowsProvider.future);
    expect(pending, hasLength(1));
    expect(pending.single.quarantined, isFalse);

    final precheck = await ShopDataTransitionService(db).precheck();
    expect(precheck.pendingOutboxCount, 1);
    expect(precheck.stuckOutboxCount, 0);
  });
}
