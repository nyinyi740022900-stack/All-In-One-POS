import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/settings/shop_profile_sync_repository.dart';

void main() {
  late AppDatabase db;
  late ShopProfileSyncRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ShopProfileSyncRepository(db);
  });

  tearDown(() async => db.close());

  test('sync creates a row keyed by shopId and enqueues outbox', () async {
    await repo.sync(
      shopId: 'shop-1',
      name: 'Acme Minimart',
      phone: '09123456',
      address: 'Yangon',
    );

    final rows = await db.select(db.shopProfiles).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'shop-1');
    expect(rows.single.shopId, 'shop-1');
    expect(rows.single.name, 'Acme Minimart');
    expect(rows.single.phone, '09123456');
    expect(rows.single.address, 'Yangon');

    final outbox = await db.select(db.outbox).get();
    expect(outbox.any((o) => o.entityTable == 'shop_profiles'), isTrue);
  });

  test('sync again for the same shop updates in place (one row)', () async {
    await repo.sync(shopId: 'shop-1', name: 'Old Name');
    await repo.sync(shopId: 'shop-1', name: 'New Name', phone: '09999');

    final rows = await db.select(db.shopProfiles).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'New Name');
    expect(rows.single.phone, '09999');
  });

  test('sync is a no-op for an empty shopId', () async {
    await repo.sync(shopId: '', name: 'Nothing');
    expect(await db.select(db.shopProfiles).get(), isEmpty);
  });

  test('a later sync without country never resets an already-set value '
      'back to the MM default — country is no longer editable from any '
      'screen, so omitting it must leave whatever is already there alone',
      () async {
    await repo.sync(shopId: 'shop-1', name: 'Shop', country: 'XX');
    await repo.sync(shopId: 'shop-1', name: 'Shop', phone: '09999');

    final row = (await db.select(db.shopProfiles).get()).single;
    expect(row.country, 'XX');
  });
}
