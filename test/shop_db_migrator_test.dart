import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/local/shop_db_migrator.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mm_pos_migrate_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('copyDeviceGlobalSettings copies only device keys', () async {
    final from = AppDatabase.forTesting(NativeDatabase.memory());
    final to = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(from.close);
    addTearDown(to.close);

    final fromSettings = SettingsRepository(from);
    await fromSettings.setLicenseJson('{"shopId":"s1"}');
    await fromSettings.saveLocale('my');
    await from
        .into(from.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(
            key: const Value('shop.name'),
            value: const Value('ShouldStayOnShop'),
          ),
        );

    await copyDeviceGlobalSettings(from: from, to: to);

    final toSettings = SettingsRepository(to);
    expect(await toSettings.licenseJson(), '{"shopId":"s1"}');
    expect(await toSettings.savedLocale(), 'my');
    final shopName = await (to.select(
      to.appSettings,
    )..where((s) => s.key.equals('shop.name'))).getSingleOrNull();
    expect(shopName, isNull);
  });

  test('materializeShopFileFromLegacy copies and strips device keys', () async {
    final legacyPath = AppDatabase.legacyDbPath(tmp.path);
    final legacyFile = File(legacyPath);
    final legacy = AppDatabase.forTesting(NativeDatabase(legacyFile));
    final settings = SettingsRepository(legacy);
    await settings.setLicenseJson('{"shopId":"shop-a"}');
    await settings.saveLocale('en');
    await legacy
        .into(legacy.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(
            key: const Value('shop.name'),
            value: const Value('Branch A'),
          ),
        );
    await legacy.close();

    await materializeShopFileFromLegacy(
      documentsDir: tmp.path,
      shopId: 'shop-a',
    );

    final shopFile = File(AppDatabase.pathForShop(tmp.path, 'shop-a'));
    expect(await shopFile.exists(), isTrue);
    final shop = AppDatabase.forTesting(NativeDatabase(shopFile));
    addTearDown(shop.close);
    final rows = await shop.select(shop.appSettings).get();
    final keys = rows.map((r) => r.key).toSet();
    expect(keys.contains('shop.name'), isTrue);
    expect(keys.contains('license.json'), isFalse);
    expect(keys.contains('app.locale'), isFalse);
  });

  test('deviceDbPath joins sidecar filename', () {
    expect(
      deviceDbPath('/docs'),
      p.join('/docs', AppDatabase.kDeviceDbFileName),
    );
  });
}
