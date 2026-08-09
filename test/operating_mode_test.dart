import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/onboarding/operating_mode_providers.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';

void main() {
  test('isOnlineModeProvider follows operating.mode', () async {
    final container = ProviderContainer(
      overrides: [
        operatingModeProvider.overrideWith((ref) async => 'online'),
      ],
    );
    addTearDown(container.dispose);
    await container.read(operatingModeProvider.future);
    expect(container.read(isOnlineModeProvider), isTrue);
  });

  test('showStaffModeSectionProvider is false in online mode', () async {
    final container = ProviderContainer(
      overrides: [
        operatingModeProvider.overrideWith((ref) async => 'online'),
        staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
      ],
    );
    addTearDown(container.dispose);
    await container.read(operatingModeProvider.future);
    expect(container.read(showStaffModeSectionProvider), isFalse);
  });

  test('showStaffModeSectionProvider stays true offline when already staff',
      () async {
    final container = ProviderContainer(
      overrides: [
        operatingModeProvider.overrideWith(
          (ref) async => SettingsRepository.operatingModeOffline,
        ),
        staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
      ],
    );
    addTearDown(container.dispose);
    await container.read(operatingModeProvider.future);
    await container.read(staffRoleProvider.future);
    expect(container.read(showStaffModeSectionProvider), isTrue);
  });

  test('effectiveRoleProvider ignores local role in online mode', () async {
    final container = ProviderContainer(
      overrides: [
        operatingModeProvider.overrideWith((ref) async => 'online'),
        staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
      ],
    );
    addTearDown(container.dispose);
    await container.read(operatingModeProvider.future);
    // No backend role → online defaults to owner (email session required by gate).
    expect(container.read(effectiveRoleProvider), 'owner');
  });

  test('localCalendarYmd format', () {
    expect(localCalendarYmd(DateTime(2026, 8, 9)), '2026-08-09');
  });
}
