import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    container = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(settings),
      databaseProvider.overrideWithValue(db),
      shopIdProvider.overrideWith((ref) => 'shop-1'),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  StaffController ctrl() => container.read(staffControllerProvider);

  test('defaults to owner role', () async {
    expect(await settings.staffRole(), 'owner');
  });

  test('switching to staff never needs a PIN', () async {
    expect(await ctrl().switchRole('staff'), isTrue);
    expect(await settings.staffRole(), 'staff');
  });

  test('switching back to owner with no PIN set succeeds', () async {
    await ctrl().switchRole('staff');
    expect(await ctrl().switchRole('owner', pin: ''), isTrue);
    expect(await settings.staffRole(), 'owner');
  });

  test('switching to owner with a wrong PIN fails and stays staff', () async {
    await ctrl().setPin('1234');
    await ctrl().switchRole('staff');
    expect(await ctrl().switchRole('owner', pin: '9999'), isFalse);
    expect(await settings.staffRole(), 'staff');
    // Correct PIN succeeds.
    expect(await ctrl().switchRole('owner', pin: '1234'), isTrue);
    expect(await settings.staffRole(), 'owner');
  });

  test('switching to staff needs no PIN even when one is set', () async {
    await ctrl().setPin('1234');
    expect(await ctrl().switchRole('staff'), isTrue);
    expect(await settings.staffRole(), 'staff');
  });

  test('switching to a named staff member with the right PIN stamps their id',
      () async {
    final staffRepo = container.read(staffRepositoryProvider);
    final id = await staffRepo.upsertMember(name: 'Mi Mi', pin: '1111');

    expect(await ctrl().switchToStaffMember(id, '1111'), isTrue);
    expect(await settings.staffRole(), 'staff');
    expect(await settings.activeStaffId(), id);
  });

  test('switching to a named staff member with the wrong PIN fails', () async {
    final staffRepo = container.read(staffRepositoryProvider);
    final id = await staffRepo.upsertMember(name: 'Ko Ko', pin: '2222');

    expect(await ctrl().switchToStaffMember(id, '0000'), isFalse);
    expect(await settings.staffRole(), 'owner'); // unchanged
  });

  test('switching to owner clears the active staff id', () async {
    final staffRepo = container.read(staffRepositoryProvider);
    final id = await staffRepo.upsertMember(name: 'Mi Mi', pin: '1111');
    await ctrl().switchToStaffMember(id, '1111');
    expect(await settings.activeStaffId(), id);

    await ctrl().switchRole('owner', pin: '');
    expect(await settings.activeStaffId(), isNull);
  });

  test('deactivating a staff member removes them from the active roster',
      () async {
    final staffRepo = container.read(staffRepositoryProvider);
    final id = await staffRepo.upsertMember(name: 'Su Su', pin: '3333');
    expect(await staffRepo.watchActiveMembers().first, hasLength(1));

    await staffRepo.deactivateMember(id);
    expect(await staffRepo.watchActiveMembers().first, isEmpty);
  });

  group('showStaffModeSectionProvider', () {
    ShopDevice bound(String id) =>
        ShopDevice(key: 'K-$id', deviceId: id, status: 'active', lastVerifiedAt: null);

    test('hidden for an owner on a single/no-backend device', () async {
      // No backend in the test env, so shopDevicesProvider resolves to [].
      await container.read(shopDevicesProvider.future);
      expect(container.read(showStaffModeSectionProvider), isFalse);
    });

    test('shown once a shop has 2+ devices', () async {
      final multi = ProviderContainer(overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        databaseProvider.overrideWithValue(db),
        shopIdProvider.overrideWith((ref) => 'shop-1'),
        shopDevicesProvider
            .overrideWith((ref) async => [bound('d1'), bound('d2')]),
      ]);
      addTearDown(multi.dispose);
      await multi.read(shopDevicesProvider.future);
      expect(multi.read(showStaffModeSectionProvider), isTrue);
    });

    test('always shown when already in Staff mode, even on one device',
        () async {
      await ctrl().switchRole('staff');
      // staffRoleProvider is a Drift watch() stream — give its event a tick
      // to reach the provider before reading the derived value.
      await container.read(staffRoleProvider.future);
      await container.read(shopDevicesProvider.future);
      expect(container.read(showStaffModeSectionProvider), isTrue);
    });
  });
}
