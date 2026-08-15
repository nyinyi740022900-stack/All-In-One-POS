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
  test('showStaffModeSectionProvider is false with a real account session',
      () async {
    final container = ProviderContainer(
      overrides: [
        hasRealAccountSessionProvider.overrideWithValue(true),
        staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(showStaffModeSectionProvider), isFalse);
  });

  test(
      'showStaffModeSectionProvider stays true with no account session when '
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

  test('effectiveRoleProvider ignores local role with a real account session',
      () async {
    final container = ProviderContainer(
      overrides: [
        hasRealAccountSessionProvider.overrideWithValue(true),
        staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
      ],
    );
    addTearDown(container.dispose);
    // No backend role -> a real account session defaults to owner (email
    // session required by the daily gate).
    expect(container.read(effectiveRoleProvider), 'owner');
  });

  test('localCalendarYmd format', () {
    expect(localCalendarYmd(DateTime(2026, 8, 9)), '2026-08-09');
  });

  test(
      'dailyGateNeededProvider triggers for a Free/offline-tier shop with no '
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
}
