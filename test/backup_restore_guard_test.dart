import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/local/shop_data_transition_service.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/backup/backup_service.dart';

/// Restore is the most destructive action in the app — a replace-all that
/// deletes every business row before inserting the file's. Two ways it used
/// to destroy data while reporting success:
///
///  * **Another shop's file.** The envelope recorded no `shop_id`, and
///    filenames are bare timestamps, so an owner with two shops had nothing
///    to tell two backups apart. Restoring A's file into B deleted all of
///    B's rows and inserted A's — which every read path then filters out by
///    `shop_id`, leaving an apparently empty shop, while the outbox pushed
///    A's rows against B's JWT claim and was rejected by RLS forever.
///  * **Unsynced writes.** Branch switching refuses to clear local data
///    while the outbox is non-empty (`assertSafeToClear`); restore had no
///    such guard, so an offline device's un-pushed sales were deleted and
///    the queued entries then dropped as "local row gone".
void main() {
  late AppDatabase db;
  late BackupService service;

  const shopId = 'shop-1';

  BackupService serviceFor(String activeShopId) => BackupService(
        db,
        SettingsRepository(db),
        shopId: activeShopId,
        guard: ShopDataTransitionService(db),
      );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = serviceFor(shopId);
  });

  tearDown(() async => db.close());

  test('an export records which shop it came from', () async {
    final decoded = jsonDecode(await service.exportJson()) as Map;
    expect(decoded['shopId'], shopId,
        reason: 'without this the restore side has nothing to check against.');
  });

  test('restoring another shop\'s backup is refused', () async {
    final foreign = jsonEncode({
      'app': 'mm_pos',
      'shopId': 'shop-2',
      'formatVersion': BackupService.formatVersion,
      'schemaVersion': db.schemaVersion,
      'tables': <String, dynamic>{},
    });

    expect(
      () => serviceFor(shopId).importReplaceAll(foreign),
      throwsA(isA<ShopMismatchException>()),
      reason: 'restoring shop-2\'s file while shop-1 is open would wipe '
          'shop-1 and leave rows no screen can see.',
    );
  });

  test('this shop\'s own backup still restores', () async {
    final own = jsonEncode({
      'app': 'mm_pos',
      'shopId': shopId,
      'formatVersion': BackupService.formatVersion,
      'schemaVersion': db.schemaVersion,
      'tables': <String, dynamic>{},
    });
    await expectLater(serviceFor(shopId).importReplaceAll(own), completes);
  });

  test('a legacy backup with no shopId is still accepted', () async {
    // Files written before the field existed make no claim about their
    // origin, so there is nothing to check — refusing them would strand
    // every backup taken to date.
    final legacy = jsonEncode({
      'app': 'mm_pos',
      'formatVersion': BackupService.formatVersion,
      'schemaVersion': db.schemaVersion,
      'tables': <String, dynamic>{},
    });
    await expectLater(serviceFor(shopId).importReplaceAll(legacy), completes);
  });

  test('a file that is not a backup at all is still rejected', () async {
    expect(
      () => service.importReplaceAll(jsonEncode({'app': 'something_else'})),
      throwsA(isA<FormatException>()),
    );
  });
}
