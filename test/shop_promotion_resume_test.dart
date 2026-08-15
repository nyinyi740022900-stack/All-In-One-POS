import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/local/database_session.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';

/// Covers the crash-recovery path for a Free-plan shop-identity promotion
/// (`ShopDataTransitionService.promoteShopIdentity` + the subsequent file
/// rename in `DatabaseSession.reopenForShopPromotedFrom`) — a device that
/// crashed mid-promotion must not silently see zero rows on next launch
/// because `license.json` and the on-disk file/shop_id columns disagree.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  const from = 'free-device1';
  const to = 'shop-real1';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mm_pos_promote_resume_');
    // resolvePendingShopPromotion opens the source shop file via the
    // production AppDatabase.forFile (not .forTesting), which calls
    // path_provider's getTemporaryDirectory for sqlite3's temp store — no
    // real platform channel exists under `flutter test`, so stub it.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<AppDatabase> openDevice() async {
    final device = AppDatabase.forTesting(
      NativeDatabase(File('${tmp.path}/mm_pos_device.sqlite')),
    );
    addTearDown(device.close);
    return device;
  }

  test('no-op when there is no pending promotion marker', () async {
    final device = await openDevice();
    // Should return without throwing and without touching anything.
    await resolvePendingShopPromotion(tmp.path, device);
    expect(await SettingsRepository(device).pendingShopPromotion(), isNull);
  });

  test(
      'crash before the data rewrite committed: resumes by re-running the '
      '(idempotent) rewrite, then renames and fixes up license.json',
      () async {
    final device = await openDevice();
    final settings = SettingsRepository(device);
    await settings.setLicenseJson(jsonEncode({'shop_id': from, 'key': 'X'}));
    await settings.setPendingShopPromotion(from, to);

    final fromFile = File(AppDatabase.pathForShop(tmp.path, from));
    final fromDb = AppDatabase.forTesting(NativeDatabase(fromFile));
    await fromDb.into(fromDb.categories).insert(
          CategoriesCompanion.insert(
            id: 'c1',
            shopId: from,
            name: 'Drinks',
            updatedAt: Value(DateTime.now()),
          ),
        );
    await fromDb.close();

    await resolvePendingShopPromotion(tmp.path, device);

    expect(await fromFile.exists(), isFalse);
    final toFile = File(AppDatabase.pathForShop(tmp.path, to));
    expect(await toFile.exists(), isTrue);
    final toDb = AppDatabase.forTesting(NativeDatabase(toFile));
    addTearDown(toDb.close);
    final rows = await toDb.select(toDb.categories).get();
    expect(rows.single.shopId, to);
    // The rewrite's own outbox backfill ran too, not just the rename.
    final outbox = await toDb.select(toDb.outbox).get();
    expect(outbox.map((o) => o.rowId), contains('c1'));

    expect(await settings.licenseJson(), contains('"shop_id":"$to"'));
    expect(await settings.pendingShopPromotion(), isNull);
  });

  test(
      'crash after the rename already completed: resumes by just fixing up '
      "license.json (doesn't touch the already-correct file again)",
      () async {
    final device = await openDevice();
    final settings = SettingsRepository(device);
    await settings.setLicenseJson(jsonEncode({'shop_id': from, 'key': 'X'}));
    await settings.setPendingShopPromotion(from, to);

    // The rename already happened before the crash; only the toShopId file
    // exists, already correctly labeled.
    final toFile = File(AppDatabase.pathForShop(tmp.path, to));
    final toDb = AppDatabase.forTesting(NativeDatabase(toFile));
    await toDb.into(toDb.categories).insert(
          CategoriesCompanion.insert(
            id: 'c1',
            shopId: to,
            name: 'Drinks',
            updatedAt: Value(DateTime.now()),
          ),
        );
    await toDb.close();

    await resolvePendingShopPromotion(tmp.path, device);

    expect(await toFile.exists(), isTrue);
    final reopened = AppDatabase.forTesting(NativeDatabase(toFile));
    addTearDown(reopened.close);
    final rows = await reopened.select(reopened.categories).get();
    expect(rows.single.shopId, to); // untouched, already correct

    expect(await settings.licenseJson(), contains('"shop_id":"$to"'));
    expect(await settings.pendingShopPromotion(), isNull);
  });
}
