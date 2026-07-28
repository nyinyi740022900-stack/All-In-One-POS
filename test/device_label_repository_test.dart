import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/settings/device_label_repository.dart';

void main() {
  late AppDatabase db;
  late DeviceLabelRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DeviceLabelRepository(db, 'shop-1');
  });

  tearDown(() async => db.close());

  test('setLabel creates a row and enqueues outbox', () async {
    await repo.setLabel('device-1', 'Counter A');
    expect(await repo.labelFor('device-1'), 'Counter A');

    final outbox = await db.select(db.outbox).get();
    expect(outbox.any((o) => o.entityTable == 'device_labels'), isTrue);
  });

  test('setLabel again for the same device renames in place (one row)',
      () async {
    await repo.setLabel('device-1', 'Counter A');
    await repo.setLabel('device-1', 'Front register');

    final rows = await db.select(db.deviceLabels).get();
    expect(rows, hasLength(1));
    expect(rows.single.label, 'Front register');
  });

  test('labelFor an unset device returns null', () async {
    expect(await repo.labelFor('unknown-device'), isNull);
  });

  test('watchAll excludes deleted rows and other shops', () async {
    await repo.setLabel('device-1', 'Counter A');
    final otherShop = DeviceLabelRepository(db, 'shop-2');
    await otherShop.setLabel('device-2', 'Other shop device');

    final rows = await repo.watchAll().first;
    expect(rows, hasLength(1));
    expect(rows.single.deviceId, 'device-1');
  });
}
