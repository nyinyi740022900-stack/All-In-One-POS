
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';

final shopProfileSyncRepositoryProvider =
    Provider<ShopProfileSyncRepository>((ref) {
  return ShopProfileSyncRepository(ref.watch(databaseProvider));
});

/// Mirrors `ShopProfile`'s name/phone/address/country/currency into the
/// synced `ShopProfiles` table, so the admin console can show them without
/// the shop having published a public Storefront. The authoritative local
/// copy stays `SettingsRepository`'s `AppSettings` KV entries — this is a
/// write-through sync target, not a replacement for it.
class ShopProfileSyncRepository {
  ShopProfileSyncRepository(this._db);

  final AppDatabase _db;

  Future<void> sync({
    required String shopId,
    required String name,
    String? phone,
    String? address,
    String? country,
    String? currencyCode,
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
              // Absent (not forced to 'MM') when the caller doesn't pass one
              // — country is no longer editable from any screen, and this
              // must never clobber whatever value is already on the remote
              // row on an unrelated profile save. A brand-new row still gets
              // the table's own 'MM' default.
              country: country == null ? const Value.absent() : Value(country),
              // Same never-clobber shape for currency — a plain profile
              // save (name/phone/address) must not touch it; only a real
              // currency change (already lock-checked by
              // SettingsRepository.setShopCurrency) passes this non-null.
              currencyCode: currencyCode == null
                  ? const Value.absent()
                  : Value(currencyCode),
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
