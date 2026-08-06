import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../repositories/settings_repository.dart';
import 'database.dart';

/// Copy device-global AppSettings rows from [from] into [to].
Future<void> copyDeviceGlobalSettings({
  required AppDatabase from,
  required AppDatabase to,
}) async {
  final rows = await from.select(from.appSettings).get();
  for (final row in rows) {
    if (!SettingsRepository.isDeviceGlobalKey(row.key)) continue;
    await to
        .into(to.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(key: Value(row.key), value: Value(row.value)),
        );
  }
}

/// Copy legacy file to per-shop path and strip device-global keys from the copy.
Future<void> materializeShopFileFromLegacy({
  required String documentsDir,
  required String shopId,
}) async {
  final legacyPath = AppDatabase.legacyDbPath(documentsDir);
  final shopFile = File(AppDatabase.pathForShop(documentsDir, shopId));
  if (await shopFile.exists()) return;
  if (!await File(legacyPath).exists()) {
    final db = AppDatabase.forTesting(NativeDatabase(shopFile));
    await db.customSelect('SELECT 1').get();
    await db.close();
    return;
  }
  await File(legacyPath).copy(shopFile.path);
  final shopDb = AppDatabase.forTesting(NativeDatabase(shopFile));
  try {
    final rows = await shopDb.select(shopDb.appSettings).get();
    for (final row in rows) {
      if (!SettingsRepository.isDeviceGlobalKey(row.key)) continue;
      await (shopDb.delete(
        shopDb.appSettings,
      )..where((s) => s.key.equals(row.key))).go();
    }
  } finally {
    await shopDb.close();
  }
}

String deviceDbPath(String documentsDir) =>
    p.join(documentsDir, AppDatabase.kDeviceDbFileName);
