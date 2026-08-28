import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/account/account_providers.dart';
import 'package:mm_pos/features/onboarding/operating_mode_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';

void main() {
  test(
    'showStaffModeSectionProvider is false for an email staff session',
    () async {
      final container = ProviderContainer(
        overrides: [
          hasRealAccountSessionProvider.overrideWithValue(true),
          backendAccountRoleProvider.overrideWithValue('staff'),
          staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(showStaffModeSectionProvider), isFalse);
    },
  );

  test('showStaffModeSectionProvider is true for an email owner so they can '
      'set or change the device PIN', () async {
    final container = ProviderContainer(
      overrides: [
        hasRealAccountSessionProvider.overrideWithValue(true),
        backendAccountRoleProvider.overrideWithValue('owner'),
        staffRoleProvider.overrideWith((ref) => Stream.value('owner')),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(showStaffModeSectionProvider), isTrue);
  });

  test('showStaffModeSectionProvider stays true with no account session when '
      'already staff', () async {
    final container = ProviderContainer(
      overrides: [
        hasRealAccountSessionProvider.overrideWithValue(false),
        staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
      ],
    );
    addTearDown(container.dispose);
    await container.read(staffRoleProvider.future);
    expect(container.read(showStaffModeSectionProvider), isTrue);
  });

  test('showStaffModeSectionProvider is true for an unsigned owner on one '
      'device', () async {
    final container = ProviderContainer(
      overrides: [
        hasRealAccountSessionProvider.overrideWithValue(false),
        backendAccountRoleProvider.overrideWithValue(null),
        staffRoleProvider.overrideWith((ref) => Stream.value('owner')),
      ],
    );
    addTearDown(container.dispose);
    await container.read(staffRoleProvider.future);
    expect(container.read(showStaffModeSectionProvider), isTrue);
  });

  test('effectiveRoleProvider keeps invited email staff as staff even if the '
      'local PIN role is owner', () async {
    final container = ProviderContainer(
      overrides: [
        hasRealAccountSessionProvider.overrideWithValue(true),
        backendAccountRoleProvider.overrideWithValue('staff'),
        staffRoleProvider.overrideWith((ref) => Stream.value('owner')),
      ],
    );
    addTearDown(container.dispose);
    await container.read(staffRoleProvider.future);
    expect(container.read(effectiveRoleProvider), 'staff');
  });

  test('effectiveRoleProvider lets an email owner follow the local PIN role',
      () async {
    final owner = ProviderContainer(
      overrides: [
        hasRealAccountSessionProvider.overrideWithValue(true),
        backendAccountRoleProvider.overrideWithValue('owner'),
        staffRoleProvider.overrideWith((ref) => Stream.value('owner')),
      ],
    );
    addTearDown(owner.dispose);
    await owner.read(staffRoleProvider.future);
    expect(owner.read(effectiveRoleProvider), 'owner');

    final staff = ProviderContainer(
      overrides: [
        hasRealAccountSessionProvider.overrideWithValue(true),
        backendAccountRoleProvider.overrideWithValue('owner'),
        staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
      ],
    );
    addTearDown(staff.dispose);
    await staff.read(staffRoleProvider.future);
    expect(staff.read(effectiveRoleProvider), 'staff');
  });

  test('unsigned device with local staff role stays staff — email-staff '
      'sign-out must not promote the device to owner', () async {
    final container = ProviderContainer(
      overrides: [
        hasRealAccountSessionProvider.overrideWithValue(false),
        backendAccountRoleProvider.overrideWithValue(null),
        staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
      ],
    );
    addTearDown(container.dispose);
    await container.read(staffRoleProvider.future);
    expect(container.read(effectiveRoleProvider), 'staff');
  });

  test('localCalendarYmd format', () {
    expect(localCalendarYmd(DateTime(2026, 8, 9)), '2026-08-09');
  });

  test('dailyGateNeededProvider triggers for a Free/offline-tier shop with no '
      'operating.mode set — previously inexpressible, since the old '
      'provider hard-returned false unless mode == online', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = SettingsRepository(db);
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        databaseProvider.overrideWithValue(db),
        shopIdProvider.overrideWith((ref) => 'free-device1'),
      ],
    );
    addTearDown(container.dispose);
    // operating.mode was never set on this device (Free plan never went
    // through a mode choice) and no gate has completed yet today.
    expect(await container.read(dailyGateNeededProvider.future), isTrue);
  });

  test('dailyGateNeededProvider is false once completed for today', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = SettingsRepository(db);
    await settings.markDailyGateComplete(
      'shop-1',
      ymd: localCalendarYmd(),
      skippedOpen: true,
    );
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        databaseProvider.overrideWithValue(db),
        shopIdProvider.overrideWith((ref) => 'shop-1'),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(dailyGateNeededProvider.future), isFalse);
  });

  test('dailyGateNeededProvider is true while shopId is still empty', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = SettingsRepository(db);
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        databaseProvider.overrideWithValue(db),
        shopIdProvider.overrideWith((ref) => ''),
      ],
    );
    addTearDown(container.dispose);
    expect(await container.read(dailyGateNeededProvider.future), isTrue);
  });
}
