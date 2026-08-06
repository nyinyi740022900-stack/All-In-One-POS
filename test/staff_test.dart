import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
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

  test('setPin rejects invalid lengths (must be 4-6 digits)', () async {
    expect(() => ctrl().setPin('123'), throwsArgumentError);
    expect(() => ctrl().setPin('1234567'), throwsArgumentError);
    await ctrl().setPin('1234');
    expect(await ctrl().switchRole('staff'), isTrue);
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

  test('owner PIN is temporarily locked after too many wrong attempts',
      () async {
    await ctrl().setPin('1234');
    await ctrl().switchRole('staff');

    for (var i = 0; i < 5; i++) {
      expect(await ctrl().switchRole('owner', pin: '0000'), isFalse);
    }
    // Cooldown lock is now active: even the correct PIN is rejected.
    expect(await ctrl().switchRole('owner', pin: '1234'), isFalse);
    expect(await settings.staffRole(), 'staff');
  });

  test('owner PIN cooldown expires and unlocks owner switch', () async {
    var fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
    final timed = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(settings),
      databaseProvider.overrideWithValue(db),
      shopIdProvider.overrideWith((ref) => 'shop-1'),
      staffControllerProvider
          .overrideWith((ref) => StaffController(ref, now: () => fakeNow)),
    ]);
    addTearDown(timed.dispose);
    final timedCtrl = timed.read(staffControllerProvider);

    await timedCtrl.setPin('1234');
    await timedCtrl.switchRole('staff');
    for (var i = 0; i < 5; i++) {
      expect(await timedCtrl.switchRole('owner', pin: '0000'), isFalse);
    }
    expect(timedCtrl.ownerPinCooldownRemainingSeconds(), greaterThan(0));

    fakeNow = fakeNow.add(const Duration(seconds: 31));
    expect(timedCtrl.ownerPinCooldownRemainingSeconds(), 0);
    expect(await timedCtrl.switchRole('owner', pin: '1234'), isTrue);
    expect(await settings.staffRole(), 'owner');
  });

  test('owner PIN cooldown persists across controller recreation', () async {
    final first = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(settings),
      databaseProvider.overrideWithValue(db),
      shopIdProvider.overrideWith((ref) => 'shop-1'),
    ]);
    final firstCtrl = first.read(staffControllerProvider);
    await firstCtrl.setPin('1234');
    await firstCtrl.switchRole('staff');
    for (var i = 0; i < 5; i++) {
      expect(await firstCtrl.switchRole('owner', pin: '0000'), isFalse);
    }
    first.dispose();

    final second = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(settings),
      databaseProvider.overrideWithValue(db),
      shopIdProvider.overrideWith((ref) => 'shop-1'),
    ]);
    addTearDown(second.dispose);
    final secondCtrl = second.read(staffControllerProvider);
    // Lock is persisted: still denied even with correct PIN.
    expect(await secondCtrl.switchRole('owner', pin: '1234'), isFalse);
    expect(await settings.staffRole(), 'staff');
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

  group('applyProvisionedRole', () {
    test('sets staff role + member id with no PIN check (owner already '
        'authorized this when generating the device QR)', () async {
      await ctrl().applyProvisionedRole('staff', staffMemberId: 'staff-9');
      expect(await settings.staffRole(), 'staff');
      expect(await settings.activeStaffId(), 'staff-9');
    });

    test('sets staff role with no member id when none was picked', () async {
      await ctrl().applyProvisionedRole('staff');
      expect(await settings.staffRole(), 'staff');
      expect(await settings.activeStaffId(), isNull);
    });

    test('is a no-op for an owner-role provisioning (the device default)',
        () async {
      await ctrl().applyProvisionedRole('owner');
      expect(await settings.staffRole(), 'owner');
    });
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

  group('PIN hashing', () {
    test('owner PIN is stored hashed, not plaintext', () async {
      await ctrl().setPin('1234');
      final row = await (db.select(db.appSettings)
            ..where((s) => s.key.equals('staff.pin_hash')))
          .getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.value, startsWith('v1:'));
      expect(row.value, isNot('1234'));
      final legacy = await (db.select(db.appSettings)
            ..where((s) => s.key.equals('staff.pin')))
          .getSingleOrNull();
      expect(legacy, isNull);
    });

    test('legacy plaintext owner PIN auto-migrates on verification', () async {
      await db.into(db.appSettings).insertOnConflictUpdate(
            const AppSettingsCompanion(
              key: Value('staff.pin'),
              value: Value('1234'),
            ),
          );

      expect(await ctrl().switchRole('owner', pin: '1234'), isTrue);

      final hashed = await (db.select(db.appSettings)
            ..where((s) => s.key.equals('staff.pin_hash')))
          .getSingleOrNull();
      expect(hashed, isNotNull);
      expect(hashed!.value, startsWith('v1:'));
      final legacy = await (db.select(db.appSettings)
            ..where((s) => s.key.equals('staff.pin')))
          .getSingleOrNull();
      expect(legacy, isNull);
    });

    test('upsertMember never stores the PIN in the clear', () async {
      final staffRepo = container.read(staffRepositoryProvider);
      final id = await staffRepo.upsertMember(name: 'Aye Aye', pin: '4444');
      final stored = await staffRepo.watchActiveMembers().first;
      final member = stored.firstWhere((m) => m.id == id);
      expect(member.pin, isNot('4444'));
      expect(member.pin, startsWith('v1:'));
    });

    test('editing a member with a blank PIN keeps their existing PIN',
        () async {
      final staffRepo = container.read(staffRepositoryProvider);
      final id = await staffRepo.upsertMember(name: 'Aye Aye', pin: '4444');
      await staffRepo.upsertMember(id: id, name: 'Aye Aye (edited)', pin: null);

      expect(await staffRepo.verifyPin(id, '4444'), isNotNull);
    });

    test('a legacy plaintext PIN still verifies and is upgraded in place',
        () async {
      final staffRepo = container.read(staffRepositoryProvider);
      // Simulate a row written before hashing existed.
      final id = await staffRepo.upsertMember(name: 'Legacy', pin: '5555');
      await (db.update(db.staffMembers)..where((t) => t.id.equals(id)))
          .write(const StaffMembersCompanion(pin: Value('5555')));

      final ok = await staffRepo.verifyPin(id, '5555');
      expect(ok, isNotNull);

      final upgraded = await staffRepo.watchActiveMembers().first;
      expect(upgraded.firstWhere((m) => m.id == id).pin, startsWith('v1:'));
    });
  });

  group('showStaffModeSectionProvider', () {
    test('hidden because device-local staff mode is deprecated', () async {
      expect(container.read(showStaffModeSectionProvider), isFalse);
    });
  });
}
