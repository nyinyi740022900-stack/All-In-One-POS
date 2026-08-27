import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/account/account_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/staff/owner_permission.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        databaseProvider.overrideWithValue(db),
        shopIdProvider.overrideWith((ref) => 'shop-1'),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  StaffController ctrl() => container.read(staffControllerProvider);

  test('defaults to owner role', () async {
    expect(await settings.staffRole('shop-1'), 'owner');
  });

  test('switching to staff never needs a PIN', () async {
    expect(await ctrl().switchRole('staff'), isTrue);
    expect(await settings.staffRole('shop-1'), 'staff');
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
    expect(await settings.staffRole('shop-1'), 'owner');
  });

  test('switching to owner with a wrong PIN fails and stays staff', () async {
    await ctrl().setPin('1234');
    await ctrl().switchRole('staff');
    expect(await ctrl().switchRole('owner', pin: '9999'), isFalse);
    expect(await settings.staffRole('shop-1'), 'staff');
    // Correct PIN succeeds.
    expect(await ctrl().switchRole('owner', pin: '1234'), isTrue);
    expect(await settings.staffRole('shop-1'), 'owner');
  });

  test(
    'owner PIN is temporarily locked after too many wrong attempts',
    () async {
      await ctrl().setPin('1234');
      await ctrl().switchRole('staff');

      for (var i = 0; i < 5; i++) {
        expect(await ctrl().switchRole('owner', pin: '0000'), isFalse);
      }
      // Cooldown lock is now active: even the correct PIN is rejected.
      expect(await ctrl().switchRole('owner', pin: '1234'), isFalse);
      expect(await settings.staffRole('shop-1'), 'staff');
    },
  );

  test('owner PIN cooldown expires and unlocks owner switch', () async {
    var fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
    final timed = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        databaseProvider.overrideWithValue(db),
        shopIdProvider.overrideWith((ref) => 'shop-1'),
        staffControllerProvider.overrideWith(
          (ref) => StaffController(ref, now: () => fakeNow),
        ),
      ],
    );
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
    expect(await settings.staffRole('shop-1'), 'owner');
  });

  test('owner PIN cooldown persists across controller recreation', () async {
    final first = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        databaseProvider.overrideWithValue(db),
        shopIdProvider.overrideWith((ref) => 'shop-1'),
      ],
    );
    final firstCtrl = first.read(staffControllerProvider);
    await firstCtrl.setPin('1234');
    await firstCtrl.switchRole('staff');
    for (var i = 0; i < 5; i++) {
      expect(await firstCtrl.switchRole('owner', pin: '0000'), isFalse);
    }
    first.dispose();

    final second = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        databaseProvider.overrideWithValue(db),
        shopIdProvider.overrideWith((ref) => 'shop-1'),
      ],
    );
    addTearDown(second.dispose);
    final secondCtrl = second.read(staffControllerProvider);
    // Lock is persisted: still denied even with correct PIN.
    expect(await secondCtrl.switchRole('owner', pin: '1234'), isFalse);
    expect(await settings.staffRole('shop-1'), 'staff');
  });

  test('switching to staff needs no PIN even when one is set', () async {
    await ctrl().setPin('1234');
    expect(await ctrl().switchRole('staff'), isTrue);
    expect(await settings.staffRole('shop-1'), 'staff');
  });

  test(
    'switching to a named staff member with the right PIN stamps their id',
    () async {
      final staffRepo = container.read(staffRepositoryProvider);
      final id = await staffRepo.upsertMember(name: 'Mi Mi', pin: '1111');

      expect(await ctrl().switchToStaffMember(id, '1111'), isTrue);
      expect(await settings.staffRole('shop-1'), 'staff');
      expect(await settings.activeStaffId('shop-1'), id);
    },
  );

  group('applyProvisionedRole', () {
    test('sets staff role + member id with no PIN check (owner already '
        'authorized this when generating the device QR)', () async {
      await ctrl().applyProvisionedRole('staff', staffMemberId: 'staff-9');
      expect(await settings.staffRole('shop-1'), 'staff');
      expect(await settings.activeStaffId('shop-1'), 'staff-9');
    });

    test('sets staff role with no member id when none was picked', () async {
      await ctrl().applyProvisionedRole('staff');
      expect(await settings.staffRole('shop-1'), 'staff');
      expect(await settings.activeStaffId('shop-1'), isNull);
    });

    test(
      'is a no-op for an owner-role provisioning (the device default)',
      () async {
        await ctrl().applyProvisionedRole('owner');
        expect(await settings.staffRole('shop-1'), 'owner');
      },
    );
  });

  test('switching to a named staff member with the wrong PIN fails', () async {
    final staffRepo = container.read(staffRepositoryProvider);
    final id = await staffRepo.upsertMember(name: 'Ko Ko', pin: '2222');

    expect(await ctrl().switchToStaffMember(id, '0000'), isFalse);
    expect(await settings.staffRole('shop-1'), 'owner'); // unchanged
  });

  test('switching to owner clears the active staff id', () async {
    final staffRepo = container.read(staffRepositoryProvider);
    final id = await staffRepo.upsertMember(name: 'Mi Mi', pin: '1111');
    await ctrl().switchToStaffMember(id, '1111');
    expect(await settings.activeStaffId('shop-1'), id);

    await ctrl().switchRole('owner', pin: '');
    expect(await settings.activeStaffId('shop-1'), isNull);
  });

  test(
    'deactivating a staff member removes them from the active roster',
    () async {
      final staffRepo = container.read(staffRepositoryProvider);
      final id = await staffRepo.upsertMember(name: 'Su Su', pin: '3333');
      expect(await staffRepo.watchActiveMembers().first, hasLength(1));

      await staffRepo.deactivateMember(id);
      expect(await staffRepo.watchActiveMembers().first, isEmpty);
    },
  );

  group('PIN hashing', () {
    test('owner PIN is stored hashed, not plaintext', () async {
      await ctrl().setPin('1234');
      final row = await (db.select(
        db.appSettings,
      )..where((s) => s.key.equals('staff.pin_hash.shop-1'))).getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.value, startsWith('v1:'));
      expect(row.value, isNot('1234'));
      final legacy = await (db.select(
        db.appSettings,
      )..where((s) => s.key.equals('staff.pin.shop-1'))).getSingleOrNull();
      expect(legacy, isNull);
    });

    test('legacy plaintext owner PIN auto-migrates on verification', () async {
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            const AppSettingsCompanion(
              key: Value('staff.pin'),
              value: Value('1234'),
            ),
          );

      expect(await ctrl().switchRole('owner', pin: '1234'), isTrue);

      final hashed = await (db.select(
        db.appSettings,
      )..where((s) => s.key.equals('staff.pin_hash.shop-1'))).getSingleOrNull();
      expect(hashed, isNotNull);
      expect(hashed!.value, startsWith('v1:'));
      final legacy = await (db.select(
        db.appSettings,
      )..where((s) => s.key.equals('staff.pin.shop-1'))).getSingleOrNull();
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

    test(
      'editing a member with a blank PIN keeps their existing PIN',
      () async {
        final staffRepo = container.read(staffRepositoryProvider);
        final id = await staffRepo.upsertMember(name: 'Aye Aye', pin: '4444');
        await staffRepo.upsertMember(
          id: id,
          name: 'Aye Aye (edited)',
          pin: null,
        );

        expect(await staffRepo.verifyPin(id, '4444'), isNotNull);
      },
    );

    test(
      'a legacy plaintext PIN still verifies and is upgraded in place',
      () async {
        final staffRepo = container.read(staffRepositoryProvider);
        // Simulate a row written before hashing existed.
        final id = await staffRepo.upsertMember(name: 'Legacy', pin: '5555');
        await (db.update(db.staffMembers)..where((t) => t.id.equals(id))).write(
          const StaffMembersCompanion(pin: Value('5555')),
        );

        final ok = await staffRepo.verifyPin(id, '5555');
        expect(ok, isNotNull);

        final upgraded = await staffRepo.watchActiveMembers().first;
        expect(upgraded.firstWhere((m) => m.id == id).pin, startsWith('v1:'));
      },
    );
  });

  group('showStaffModeSectionProvider', () {
    test('shown for an unsigned owner even on a single/no-backend device', () {
      expect(container.read(showStaffModeSectionProvider), isTrue);
    });

    test(
      'always shown when already in Staff mode, even on one device',
      () async {
        await ctrl().switchRole('staff');
        // staffRoleProvider is a Drift watch() stream — give its event a tick
        // to reach the provider before reading the derived value.
        await container.read(staffRoleProvider.future);
        expect(container.read(showStaffModeSectionProvider), isTrue);
      },
    );
  });

  group('StaffPermissions (owner-granted per-staff-member capabilities)', () {
    test('a new staff member starts with zero grants (default-deny)', () async {
      final staffRepo = container.read(staffRepositoryProvider);
      final id = await staffRepo.upsertMember(name: 'Thanda', pin: '1111');
      expect(await staffRepo.watchGrantedCapabilities(id).first, isEmpty);
    });

    test('granting a capability makes it show up, revoking removes it',
        () async {
      final staffRepo = container.read(staffRepositoryProvider);
      final id = await staffRepo.upsertMember(name: 'Thanda', pin: '1111');

      await staffRepo.setCapabilityGranted(
        id,
        OwnerCapability.inventoryEdit,
        true,
      );
      expect(
        await staffRepo.watchGrantedCapabilities(id).first,
        {OwnerCapability.inventoryEdit},
      );

      await staffRepo.setCapabilityGranted(
        id,
        OwnerCapability.inventoryEdit,
        false,
      );
      expect(await staffRepo.watchGrantedCapabilities(id).first, isEmpty);
    });

    test('re-granting a previously revoked capability flips the same row '
        'back on (no duplicate rows)', () async {
      final staffRepo = container.read(staffRepositoryProvider);
      final id = await staffRepo.upsertMember(name: 'Thanda', pin: '1111');

      await staffRepo.setCapabilityGranted(
        id,
        OwnerCapability.branches,
        true,
      );
      await staffRepo.setCapabilityGranted(
        id,
        OwnerCapability.branches,
        false,
      );
      await staffRepo.setCapabilityGranted(
        id,
        OwnerCapability.branches,
        true,
      );

      final rows = await (db.select(db.staffPermissions)
            ..where((t) => t.staffMemberId.equals(id)))
          .get();
      expect(rows, hasLength(1));
      expect(
        await staffRepo.watchGrantedCapabilities(id).first,
        {OwnerCapability.branches},
      );
    });

    test('grants are isolated per staff member — granting one never leaks '
        'into another', () async {
      final staffRepo = container.read(staffRepositoryProvider);
      final a = await staffRepo.upsertMember(name: 'Staff A', pin: '1111');
      final b = await staffRepo.upsertMember(name: 'Staff B', pin: '2222');

      await staffRepo.setCapabilityGranted(
        a,
        OwnerCapability.staffAccounts,
        true,
      );

      expect(
        await staffRepo.watchGrantedCapabilities(a).first,
        {OwnerCapability.staffAccounts},
      );
      expect(await staffRepo.watchGrantedCapabilities(b).first, isEmpty);
    });

    test('revoking a capability nobody ever granted is a harmless no-op',
        () async {
      final staffRepo = container.read(staffRepositoryProvider);
      final id = await staffRepo.upsertMember(name: 'Thanda', pin: '1111');

      await staffRepo.setCapabilityGranted(
        id,
        OwnerCapability.license,
        false,
      );
      expect(await staffRepo.watchGrantedCapabilities(id).first, isEmpty);
      final rows = await (db.select(db.staffPermissions)
            ..where((t) => t.staffMemberId.equals(id)))
          .get();
      expect(rows, isEmpty);
    });

    test('activeStaffGrantedCapabilitiesProvider resolves the switched-in '
        "member's grants, empty for owner or plain (unnamed) staff mode",
        () async {
      final staffRepo = container.read(staffRepositoryProvider);
      final id = await staffRepo.upsertMember(name: 'Thanda', pin: '1111');
      await staffRepo.setCapabilityGranted(
        id,
        OwnerCapability.inventoryEdit,
        true,
      );

      // Owner mode: grants never apply, even though some exist.
      expect(
        container.read(activeStaffGrantedCapabilitiesProvider),
        isEmpty,
      );

      // Plain (unnamed) staff mode: no active staff id selected.
      await ctrl().switchRole('staff');
      await container.read(activeStaffIdProvider.future);
      expect(
        container.read(activeStaffGrantedCapabilitiesProvider),
        isEmpty,
      );

      // Switched in as the named member: their grant resolves live.
      await ctrl().switchRole('owner', pin: '');
      await ctrl().switchToStaffMember(id, '1111');
      await container.read(staffRoleProvider.future);
      await container.read(activeStaffIdProvider.future);
      await container.read(staffGrantedCapabilitiesProvider(id).future);
      expect(
        container.read(activeStaffGrantedCapabilitiesProvider),
        {OwnerCapability.inventoryEdit},
      );
    });

    test('hasOwnerCapabilityProvider combines owner-or-granted, matching '
        "OwnerPermissionPolicy.allows' contract", () async {
      final staffRepo = container.read(staffRepositoryProvider);
      final id = await staffRepo.upsertMember(name: 'Thanda', pin: '1111');
      await staffRepo.setCapabilityGranted(
        id,
        OwnerCapability.storefront,
        true,
      );

      await ctrl().switchToStaffMember(id, '1111');
      await container.read(staffRoleProvider.future);
      await container.read(activeStaffIdProvider.future);
      await container.read(staffGrantedCapabilitiesProvider(id).future);

      expect(
        container.read(
          hasOwnerCapabilityProvider(OwnerCapability.storefront),
        ),
        isTrue,
      );
      // Not granted for this member — still denied.
      expect(
        container.read(hasOwnerCapabilityProvider(OwnerCapability.branches)),
        isFalse,
      );
    });
  });

  group(
    'email-linked staff account (invited StaffAccount ↔ StaffMember)',
    () {
      ProviderContainer emailSessionContainer({
        required String? backendRole,
        required String? email,
      }) {
        final c = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settings),
            databaseProvider.overrideWithValue(db),
            shopIdProvider.overrideWith((ref) => 'shop-1'),
            backendAccountRoleProvider.overrideWithValue(backendRole),
            currentAccountEmailProvider.overrideWithValue(email),
          ],
        );
        addTearDown(c.dispose);
        return c;
      }

      test(
        'a roster member with a matching email (case-insensitive) inherits '
        'their grants under a backend staff session',
        () async {
          final staffRepo = container.read(staffRepositoryProvider);
          final id = await staffRepo.upsertMember(
            name: 'Thanda',
            pin: '1111',
            email: 'thanda@shop.com',
          );
          await staffRepo.setCapabilityGranted(
            id,
            OwnerCapability.analytics,
            true,
          );

          final scoped = emailSessionContainer(
            backendRole: 'staff',
            email: 'THANDA@Shop.com',
          );
          await scoped.read(staffMembersProvider.future);
          expect(scoped.read(emailLinkedStaffMemberProvider)?.id, id);
          await scoped.read(staffGrantedCapabilitiesProvider(id).future);
          expect(
            scoped.read(activeStaffGrantedCapabilitiesProvider),
            {OwnerCapability.analytics},
          );
          expect(
            scoped.read(
              hasResolvedOwnerCapabilityProvider(OwnerCapability.analytics),
            ),
            isTrue,
          );
          // Not granted for this member — still denied.
          expect(
            scoped.read(
              hasResolvedOwnerCapabilityProvider(OwnerCapability.branches),
            ),
            isFalse,
          );
        },
      );

      test(
        'no roster member matches the signed-in email — no grants inherited '
        '(safe default-deny)',
        () async {
          final scoped = emailSessionContainer(
            backendRole: 'staff',
            email: 'nobody@shop.com',
          );
          await scoped.read(staffMembersProvider.future);
          expect(scoped.read(emailLinkedStaffMemberProvider), isNull);
          expect(scoped.read(activeStaffGrantedCapabilitiesProvider), isEmpty);
        },
      );

      test(
        'a backend owner session is unaffected by email linking — still '
        'full access regardless of roster email matches',
        () async {
          final scoped = emailSessionContainer(
            backendRole: 'owner',
            email: 'owner@shop.com',
          );
          await scoped.read(staffRoleProvider.future);
          expect(scoped.read(emailLinkedStaffMemberProvider), isNull);
          expect(
            scoped.read(
              hasResolvedOwnerCapabilityProvider(OwnerCapability.analytics),
            ),
            isTrue,
          );
        },
      );
    },
  );

  test('ownerPinIsSetProvider follows the active shop', () async {
    final scoped = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(scoped.dispose);

    scoped.read(shopIdProvider.notifier).state = 'shop-a';
    await scoped.read(staffControllerProvider).setPin('1234');
    expect(await scoped.read(ownerPinIsSetProvider.future), isTrue);

    scoped.read(shopIdProvider.notifier).state = 'shop-b';
    expect(await scoped.read(ownerPinIsSetProvider.future), isFalse);

    scoped.read(shopIdProvider.notifier).state = 'shop-a';
    expect(await scoped.read(ownerPinIsSetProvider.future), isTrue);
  });
}
