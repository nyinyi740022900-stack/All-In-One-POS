
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';

final shopProfileSyncRepositoryProvider =
    Provider<ShopProfileSyncRepository>((ref) {
  return ShopProfileSyncRepository(ref.watch(databaseProvider));
});

/// Mirrors just the contact fields of `ShopProfile` (name/phone/address)
/// into the synced `ShopProfiles` table, so the admin console can show them
/// without the shop having published a public Storefront. The authoritative
/// local copy stays `SettingsRepository`'s `AppSettings` KV entries — this
/// is a write-through sync target, not a replacement for it.
class ShopProfileSyncRepository {
  ShopProfileSyncRepository(this._db);

  final AppDatabase _db;

  Future<void> sync({
    required String shopId,
    required String name,
    String? phone,
    String? address,
  }) async {
    if (shopId.isEmpty) return;
    await _db.transaction(() async {
      await _db.into(_db.shopProfiles).insertOnConflictUpdate(
            ShopProfilesCompanion(
              id: Value(shopId),
              shopId: Value(shopId),
              name: Value(name),
              phone: Value(phone),
              address: Value(address),
              updatedAt: Value(DateTime.now()),
              dirty: const Value(true),
            ),
          );
      await _db.into(_db.outbox).insert(OutboxCompanion.insert(
            entityTable: 'shop_profiles',
            rowId: shopId,
            op: 'upsert',
          ));
    });
  }
}
