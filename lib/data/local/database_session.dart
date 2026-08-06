import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'database.dart';
import 'shop_db_migrator.dart';

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
