import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import '../repositories/settings_repository.dart';
import 'database.dart';
import 'shop_db_migrator.dart';
import 'shop_data_transition_service.dart';

/// Holds the open shop DB + device sidecar and can reopen the shop file on
/// branch switch (Priority C cutover).
class DatabaseSession extends ChangeNotifier {
  DatabaseSession._(this._shop, this._device, this._documentsDir, this._shopId);

  AppDatabase _shop;
  final AppDatabase _device;
  final String _documentsDir;
  String? _shopId;

  AppDatabase get shopDb => _shop;
  AppDatabase get deviceDb => _device;
  String? get shopId => _shopId;

  static Future<DatabaseSession> open() async {
    final dir = await getApplicationDocumentsDirectory();
    await _prepareSqliteEnv();
    if (!AppDatabase.usePerShopDbFiles) {
      final legacy = AppDatabase.forFile(
        File(AppDatabase.legacyDbPath(dir.path)),
      );
      return DatabaseSession._(legacy, legacy, dir.path, null);
    }
    return _openCutover(dir.path);
  }

  static Future<DatabaseSession> _openCutover(String documentsDir) async {
    final deviceFile = File(
      p.join(documentsDir, AppDatabase.kDeviceDbFileName),
    );
    final legacyFile = File(AppDatabase.legacyDbPath(documentsDir));
    final device = AppDatabase.forFile(deviceFile);

    // Finish an interrupted Free-plan shop-identity promotion (crash between
    // the data rewrite and the file rename) before deciding which shop file
    // to open below — otherwise license.json and the on-disk file/shop_id
    // columns could disagree, and every shop-scoped query would silently
    // see zero rows.
    await resolvePendingShopPromotion(documentsDir, device);

    var shopId = await licenseShopIdFrom(device);
    if ((shopId == null || shopId.isEmpty) && await legacyFile.exists()) {
      final legacy = AppDatabase.forFile(legacyFile);
      try {
        shopId = await licenseShopIdFrom(legacy);
        await copyDeviceGlobalSettings(from: legacy, to: device);
      } finally {
        await legacy.close();
      }
      if (shopId != null && shopId.isNotEmpty) {
        await materializeShopFileFromLegacy(
          documentsDir: documentsDir,
          shopId: shopId,
        );
      }
      if (await legacyFile.exists()) {
        final bak = File('${legacyFile.path}.bak');
        if (await bak.exists()) await bak.delete();
        await legacyFile.rename(bak.path);
      }
    }

    final shopPath = (shopId == null || shopId.isEmpty)
        ? AppDatabase.legacyDbPath(documentsDir)
        : AppDatabase.pathForShop(documentsDir, shopId);
    final shop = AppDatabase.forFile(File(shopPath));
    return DatabaseSession._(shop, device, documentsDir, shopId);
  }

  /// Close current shop DB and open [toShopId]'s file (create empty if new).
  Future<void> reopenForShop(String toShopId) async {
    if (!AppDatabase.usePerShopDbFiles) return;
    if (toShopId.isEmpty) return;
    if (_shopId == toShopId) return;

    final nextFile = File(AppDatabase.pathForShop(_documentsDir, toShopId));
    final next = AppDatabase.forFile(nextFile);
    final previous = _shop;
    _shop = next;
    _shopId = toShopId;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    if (!identical(previous, _device)) {
      await previous.close();
    }
  }

  /// Promotes the currently-open shop (already rewritten in place by
  /// `ShopDataTransitionService.promoteShopIdentity`) to [toShopId] by
  /// renaming its file, then reopens at the new path — used when a
  /// Free-plan shop redeems a key or signs up for real, so its local data
  /// travels with it instead of a plain [reopenForShop] opening an empty
  /// file at the new id and orphaning it. Closes the current connection
  /// first (renaming an open SQLite file is unsafe); skips the rename if
  /// the target file already exists (a resumed promotion — see
  /// [resolvePendingShopPromotion] — may have already finished it).
  Future<void> reopenForShopPromotedFrom({
    required String fromShopId,
    required String toShopId,
  }) async {
    if (!AppDatabase.usePerShopDbFiles) return;
    if (toShopId.isEmpty || toShopId == fromShopId) return;
    final fromFile = File(AppDatabase.pathForShop(_documentsDir, fromShopId));
    final toFile = File(AppDatabase.pathForShop(_documentsDir, toShopId));
    final previous = _shop;
    await previous.close();
    if (!await toFile.exists() && await fromFile.exists()) {
      await fromFile.rename(toFile.path);
    }
    _shop = AppDatabase.forFile(toFile);
    _shopId = toShopId;
    notifyListeners();
  }

  Future<void> disposeSessions() async {
    if (!identical(_shop, _device)) {
      await _shop.close();
      await _device.close();
    } else {
      await _shop.close();
    }
  }

  static Future<void> _prepareSqliteEnv() async {
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;
  }
}

Future<String?> licenseShopIdFrom(AppDatabase db) async {
  final row = await (db.select(
    db.appSettings,
  )..where((s) => s.key.equals('license.json'))).getSingleOrNull();
  if (row == null) return null;
  try {
    final map = jsonDecode(row.value) as Map<String, dynamic>;
    return map['shopId'] as String? ?? map['shop_id'] as String?;
  } catch (_) {
    return null;
  }
}

/// If a Free-plan shop-identity promotion (see
/// `ShopDataTransitionService.promoteShopIdentity`) was interrupted between
/// its data rewrite and the file rename, finishes it before the caller
/// decides which shop file to open — otherwise `license.json` and the
/// on-disk file/`shop_id` columns could disagree, and every shop-scoped
/// query would silently see zero rows. Re-running the data rewrite here is
/// safe even if it already completed (see that method's doc comment); the
/// rename is skipped if the target file already exists.
Future<void> resolvePendingShopPromotion(
  String documentsDir,
  AppDatabase device,
) async {
  final settings = SettingsRepository(device);
  final pending = await settings.pendingShopPromotion();
  if (pending == null) return;
  final parts = pending.split('|');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
    await settings.clearPendingShopPromotion();
    return;
  }
  final fromShopId = parts[0];
  final toShopId = parts[1];
  final fromFile = File(AppDatabase.pathForShop(documentsDir, fromShopId));
  final toFile = File(AppDatabase.pathForShop(documentsDir, toShopId));
  if (!await toFile.exists() && await fromFile.exists()) {
    final shopDb = AppDatabase.forFile(fromFile);
    try {
      await ShopDataTransitionService(shopDb).promoteShopIdentity(
        fromShopId: fromShopId,
        toShopId: toShopId,
      );
    } finally {
      await shopDb.close();
    }
    await fromFile.rename(toFile.path);
  }
  // Bring license.json's shopId in line with the file we now have, so the
  // caller's own licenseShopIdFrom(device) read (right after this returns)
  // resolves to toShopId, not the stale fromShopId.
  final row = await (device.select(
    device.appSettings,
  )..where((s) => s.key.equals('license.json'))).getSingleOrNull();
  if (row != null) {
    try {
      final map = jsonDecode(row.value) as Map<String, dynamic>;
      map['shop_id'] = toShopId;
      map.remove('shopId');
      await device
          .into(device.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion(
              key: const Value('license.json'),
              value: Value(jsonEncode(map)),
            ),
          );
    } catch (_) {
      // Malformed license.json — leave it; the normal activation flow
      // re-establishes it the next time the owner opens License settings.
    }
  }
  await settings.clearPendingShopPromotion();
}
