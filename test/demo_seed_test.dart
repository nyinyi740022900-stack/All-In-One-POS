import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/demo_seed.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';

void main() {
  late AppDatabase db;
  late InventoryRepository repo;

  setUp(() {
    DemoSeed.resetInFlightForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = InventoryRepository(db, 'shop-1');
  });

  tearDown(() async => db.close());


  test('disabled seed never inserts, even on an empty shop', () async {
    await DemoSeed(db, repo, 'shop-1', enabled: false).ensureSeeded();
    expect(await repo.watchProducts().first, isEmpty);
  });

  test('empty shop gets the demo catalogue once', () async {
    await DemoSeed(db, repo, 'shop-1', enabled: true).ensureSeeded();
    final first = await repo.watchProducts().first;
    expect(first, hasLength(6));

    await DemoSeed(db, repo, 'shop-1', enabled: true).ensureSeeded();
    expect(await repo.watchProducts().first, hasLength(6));
  });

  test('does not add demo rows on top of products already in the shop',
      () async {
    await repo.upsertProduct(name: 'Existing', quantity: 1);
    await DemoSeed(db, repo, 'shop-1', enabled: true).ensureSeeded();
    final products = await repo.watchProducts().first;
    expect(products, hasLength(1));
    expect(products.single.product.name, 'Existing');
  });

  test('collapseDuplicates tombstones unused seed copies, keeps the used row',
      () async {
    await repo.upsertProduct(
      name: 'ဆပ်ပြာ',
      sku: 'Bar soap',
      salePrice: 800,
      quantity: 30,
    );
    final usedId = await repo.upsertProduct(
      name: 'ဆပ်ပြာ',
      sku: 'Bar soap',
      salePrice: 800,
      quantity: 30,
    );
    await repo.adjustStock(
      productId: usedId,
      delta: -1,
      type: 'adjustment',
    );

    final seed = DemoSeed(db, repo, 'shop-1', enabled: false);
    expect(await seed.collapseDuplicates(), 1);

    final live = await repo.watchProducts().first;
    final soaps = live.where((p) => p.product.name == 'ဆပ်ပြာ').toList();
    expect(soaps, hasLength(1));
    expect(soaps.single.product.id, usedId);
    expect(soaps.single.quantity, 29);
  });

  test('collapseDuplicates prefers the copy with a photo', () async {
    await repo.upsertProduct(
      name: 'ကိုကာကိုလာ (ဗူး)',
      sku: 'Coca-Cola can',
      salePrice: 700,
      quantity: 24,
    );
    final withPhoto = await repo.upsertProduct(
      name: 'ကိုကာကိုလာ (ဗူး)',
      sku: 'Coca-Cola can',
      salePrice: 700,
      quantity: 24,
      imageUrl: 'https://example.com/coke.png',
    );

    final seed = DemoSeed(db, repo, 'shop-1', enabled: false);
    expect(await seed.collapseDuplicates(), 1);
    final live = await repo.watchProducts().first;
    expect(live.single.product.id, withPhoto);
  });

  test('collapseDuplicates leaves non-demo names and unique demo rows alone',
      () async {
    await repo.upsertProduct(name: 'Custom tea', quantity: 2);
    await repo.upsertProduct(name: 'Custom tea', quantity: 3);
    await repo.upsertProduct(name: 'ဆပ်ပြာ', salePrice: 800, quantity: 30);

    final seed = DemoSeed(db, repo, 'shop-1', enabled: false);
    expect(await seed.collapseDuplicates(), 0);
    expect(await repo.watchProducts().first, hasLength(3));
  });

  test('collapseDuplicates does not tombstone real same-name products',
      () async {
    await repo.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Shop soap A', quantity: 10);
    await repo.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Shop soap B', quantity: 12);

    final seed = DemoSeed(db, repo, 'shop-1', enabled: false);
    expect(await seed.collapseDuplicates(), 0);
    expect(await repo.watchProducts().first, hasLength(2));
  });

  group('runInventoryStartupMaintenance (audit M2 one-shot flag)', () {
    Future<int> soapCount() async => (await repo.watchProducts().first)
        .where((p) => p.product.name == 'ဆပ်ပြာ')
        .length;

    test('cleans duplicates once, then the flag short-circuits later runs',
        () async {
      final settings = SettingsRepository(db);
      // Two seed copies of the same demo product.
      await repo.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Bar soap', quantity: 30);
      await repo.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Bar soap', quantity: 30);

      await runInventoryStartupMaintenance(
          db: db, repo: repo, shopId: 'shop-1', settings: settings);
      expect(await soapCount(), 1);
      expect(await settings.seedCleanupDone('shop-1'), isTrue);

      // A duplicate that appears afterwards must NOT be cleaned by later
      // mounts — the flag exists precisely so release builds stop scanning.
      await repo.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Bar soap', quantity: 30);
      await runInventoryStartupMaintenance(
          db: db, repo: repo, shopId: 'shop-1', settings: settings);
      expect(await soapCount(), 2);
    });

    test('flag is per-shop — branch switch cleans the next shop once',
        () async {
      final settings = SettingsRepository(db);
      await repo.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Bar soap', quantity: 30);
      await repo.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Bar soap', quantity: 30);

      await runInventoryStartupMaintenance(
          db: db, repo: repo, shopId: 'shop-1', settings: settings);

      final repo2 = InventoryRepository(db, 'shop-2');
      await repo2.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Bar soap', quantity: 5);
      await repo2.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Bar soap', quantity: 5);

      await runInventoryStartupMaintenance(
          db: db, repo: repo2, shopId: 'shop-2', settings: settings);

      final soaps2 = await (db.select(db.products)
            ..where((p) => p.shopId.equals('shop-2'))
            ..where((p) => p.isDeleted.equals(false)))
          .get();
      expect(soaps2, hasLength(1),
          reason: 'shop-2 gets its own first-run cleanup');
      expect(await settings.seedCleanupDone('shop-1'), isTrue);
      expect(await settings.seedCleanupDone('shop-2'), isTrue);
    });

    test('null settings keeps the legacy always-clean behaviour', () async {
      await repo.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Bar soap', quantity: 30);
      await repo.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Bar soap', quantity: 30);

      await runInventoryStartupMaintenance(
          db: db, repo: repo, shopId: 'shop-1');
      expect(await soapCount(), 1);

      await repo.upsertProduct(name: 'ဆပ်ပြာ', sku: 'Bar soap', quantity: 30);
      await runInventoryStartupMaintenance(
          db: db, repo: repo, shopId: 'shop-1');
      expect(await soapCount(), 1,
          reason: 'without a settings handle every run still cleans');
    });
  });
}
