import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/data/sync/sync_engine.dart';

/// Shared in-memory fake backend for a multi-device scenario — the same
/// instance is handed to two independent [SyncEngine]s so they can push to
/// and pull from a common "cloud".
class _SharedFakeRemote implements SyncRemote {
  final Map<String, Map<String, Map<String, dynamic>>> store = {};

  @override
  Future<void> upsert(String table, Map<String, dynamic> row) async {
    (store[table] ??= {})[row['id'] as String] = Map.of(row);
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
    // Inclusive (>=), matching SupabaseSyncRemote's `gte` filter.
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

void main() {
  test(
      'two offline devices adjusting the same product\'s stock converge to '
      'the correct combined quantity after sync, instead of one clobbering '
      'the other (regression test for the stock_levels absolute-LWW bug)',
      () async {
    final remote = _SharedFakeRemote();

    final dbA = AppDatabase.forTesting(NativeDatabase.memory());
    final inventoryA = InventoryRepository(dbA, 'shop-1');
    final settingsA = SettingsRepository(dbA);
    final engineA = SyncEngine(
        db: dbA, remote: remote, settings: settingsA, shopId: 'shop-1');

    final dbB = AppDatabase.forTesting(NativeDatabase.memory());
    final inventoryB = InventoryRepository(dbB, 'shop-1');
    final settingsB = SettingsRepository(dbB);
    final engineB = SyncEngine(
        db: dbB, remote: remote, settings: settingsB, shopId: 'shop-1');

    // Device A creates the product (quantity 0) and syncs it up.
    final productId =
        await inventoryA.upsertProduct(name: 'Coke', salePrice: 700, quantity: 0);
    await engineA.syncNow();

    // Device B pulls it down — both devices now share the same product +
    // stock_levels row, starting at quantity 0.
    await engineB.syncNow();

    // Both devices go offline and independently adjust stock.
    await inventoryA.adjustStock(productId: productId, delta: 5, type: 'purchase');
    await inventoryB.adjustStock(productId: productId, delta: -3, type: 'sale');

    // Sanity: each device only sees its own change before syncing again.
    final aBefore =
        (await inventoryA.watchProducts().first).single.quantity;
    final bBefore =
        (await inventoryB.watchProducts().first).single.quantity;
    expect(aBefore, 5);
    expect(bBefore, -3);

    // Both come back online — push then pull, in either order, repeatedly
    // until both sides have seen everything (mirrors real usage: sync isn't
    // a single atomic rendezvous between devices).
    await engineA.syncNow();
    await engineB.syncNow();
    await engineA.syncNow();
    await engineB.syncNow();

    final aAfter = (await inventoryA.watchProducts().first).single.quantity;
    final bAfter = (await inventoryB.watchProducts().first).single.quantity;

    // Correct combined result: 0 + 5 (A's purchase) - 3 (B's sale) = 2.
    // Before the fix, whichever device's absolute `stock_levels.quantity`
    // push landed last would have silently overwritten the other's change
    // (ending at 5 or -3, never the true combined 2).
    expect(aAfter, 2);
    expect(bAfter, 2);

    await dbA.close();
    await dbB.close();
  });
}
