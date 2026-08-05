import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/sync/sync_providers.dart';

/// Regression coverage for the "poison pill" outbox bug: a row that fails
/// to push forever retried silently behind an accurate "Up to date" status,
/// permanently blocking anything that requires a fully-drained outbox (e.g.
/// `BranchRepository.switchBranch`) with no way for the owner to see why or
/// resolve it. See `stuckOutboxProvider`'s doc comment and the Sync Issues
/// screen (`sync_issues_screen.dart`) this backs.
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

  Future<int> insertOutboxRow({int attempts = 0, String? lastError}) async {
    return db.into(db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'products',
          rowId: 'p1',
          op: 'upsert',
          payload: '{}',
          attempts: Value(attempts),
          lastError: Value(lastError),
        ));
  }

  test('a row below the stuck threshold does not appear', () async {
    await insertOutboxRow(attempts: kOutboxStuckThreshold - 1);
    final rows = await container.read(stuckOutboxProvider.future);
    expect(rows, isEmpty);
  });

  test('a row at or above the stuck threshold appears with its error',
      () async {
    await insertOutboxRow(attempts: kOutboxStuckThreshold, lastError: 'boom');
    final rows = await container.read(stuckOutboxProvider.future);
    expect(rows, hasLength(1));
    expect(rows.single.lastError, 'boom');
  });

  test('discardOutboxRow removes exactly that row', () async {
    final seq = await insertOutboxRow(attempts: kOutboxStuckThreshold);
    await insertOutboxRow(attempts: 0); // an unrelated, healthy row

    final controller = container.read(syncControllerProvider.notifier);
    await controller.discardOutboxRow(seq);

    final remaining = await db.select(db.outbox).get();
    expect(remaining, hasLength(1));
    expect(remaining.single.seq, isNot(seq));
  });
}
