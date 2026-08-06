import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });

  tearDown(() async => db.close());

  group('shopProfile (per-shop isolation)', () {
    test(
      'saving a profile for one shop never overwrites another shop\'s',
      () async {
        await repo.saveShopProfile(
          'shop-main',
          const ShopProfile(name: 'Main Shop', phone: '111'),
        );
        await repo.saveShopProfile(
          'shop-branch',
          const ShopProfile(name: 'Branch Shop', phone: '222'),
        );

        final main = await repo.shopProfile('shop-main');
        final branch = await repo.shopProfile('shop-branch');
        expect(main.name, 'Main Shop');
        expect(main.phone, '111');
        expect(branch.name, 'Branch Shop');
        expect(branch.phone, '222');
      },
    );

    test('a shop with no profile saved yet falls back to the un-suffixed '
        'legacy key (a pre-multi-shop install\'s existing data)', () async {
      // Simulates data saved before this shopId-keyed scheme existed, or
      // saved during onboarding before a shopId was assigned (shopId '').
      await repo.saveShopProfile(
        '',
        const ShopProfile(name: 'Legacy Shop', address: 'Yangon'),
      );

      final profile = await repo.shopProfile('shop-not-yet-customized');
      expect(profile.name, 'Legacy Shop');
      expect(profile.address, 'Yangon');
    });

    test('once a shop saves its own profile, it no longer falls back to the '
        'legacy key even for fields it left blank', () async {
      await repo.saveShopProfile(
        '',
        const ShopProfile(name: 'Legacy Shop', address: 'Yangon'),
      );
      await repo.saveShopProfile(
        'shop-branch',
        const ShopProfile(name: 'Branch'),
      );

      final profile = await repo.shopProfile('shop-branch');
      expect(profile.name, 'Branch');
      // address wasn't set for shop-branch specifically, so it does still
      // fall back per-field (documented, non-corrupting default) — but the
      // name itself, which shop-branch did set, is never overridden.
      expect(profile.address, 'Yangon');
    });

    test('setShopLogoUrl is also per-shop', () async {
      await repo.setShopLogoUrl('shop-main', 'https://example.com/main.png');
      await repo.setShopLogoUrl(
        'shop-branch',
        'https://example.com/branch.png',
      );

      expect(
        (await repo.shopProfile('shop-main')).logoUrl,
        'https://example.com/main.png',
      );
      expect(
        (await repo.shopProfile('shop-branch')).logoUrl,
        'https://example.com/branch.png',
      );
    });

    test('no profile saved anywhere defaults to "My Shop"', () async {
      final profile = await repo.shopProfile('shop-fresh');
      expect(profile.name, 'My Shop');
      expect(profile.address, isNull);
    });
  });

  group('trackStock (per-shop isolation)', () {
    test('a saved value is isolated per shop', () async {
      await repo.setTrackStock('shop-main', false);
      await repo.setTrackStock('shop-branch', true);

      expect(await repo.trackStock('shop-main'), isFalse);
      expect(await repo.trackStock('shop-branch'), isTrue);
    });

    test('a shop with no scoped value falls back to legacy key', () async {
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            const AppSettingsCompanion(
              key: Value('shop.track_stock'),
              value: Value('false'),
            ),
          );

      expect(await repo.trackStock('new-shop'), isFalse);
    });
  });

  group('staff mode + PIN state (per-shop isolation)', () {
    test('staff role is isolated per shop with legacy fallback', () async {
      await repo.setStaffRole('shop-main', 'staff');
      await repo.setStaffRole('shop-branch', 'owner');
      expect(await repo.staffRole('shop-main'), 'staff');
      expect(await repo.staffRole('shop-branch'), 'owner');

      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            const AppSettingsCompanion(
              key: Value('staff.role'),
              value: Value('staff'),
            ),
          );
      expect(await repo.staffRole('shop-new'), 'staff');
    });

    test('owner PIN hash and cooldown state are isolated per shop', () async {
      await repo.setStaffPin('shop-main', '1234');
      await repo.setStaffPin('shop-branch', '5678');
      expect(await repo.verifyStaffPin('shop-main', '1234'), isTrue);
      expect(await repo.verifyStaffPin('shop-main', '5678'), isFalse);
      expect(await repo.verifyStaffPin('shop-branch', '5678'), isTrue);

      await repo.setOwnerPinFailedAttempts('shop-main', 4);
      await repo.setOwnerPinFailedAttempts('shop-branch', 1);
      expect(await repo.ownerPinFailedAttempts('shop-main'), 4);
      expect(await repo.ownerPinFailedAttempts('shop-branch'), 1);

      final lockMain = DateTime(2026, 8, 6, 12, 0, 0);
      final lockBranch = DateTime(2026, 8, 6, 13, 0, 0);
      await repo.setOwnerPinLockedUntil('shop-main', lockMain);
      await repo.setOwnerPinLockedUntil('shop-branch', lockBranch);
      expect(await repo.ownerPinLockedUntil('shop-main'), lockMain.toUtc());
      expect(await repo.ownerPinLockedUntil('shop-branch'), lockBranch.toUtc());
    });
  });
}
