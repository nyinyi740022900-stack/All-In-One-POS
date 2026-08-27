import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/staff/owner_permission.dart';

void main() {
  const policy = OwnerPermissionPolicy();

  test('all capabilities require effective owner', () {
    for (final capability in OwnerCapability.values) {
      expect(
        policy.allows(capability, isEffectiveOwner: true),
        isTrue,
        reason: '$capability should allow owners',
      );
      expect(
        policy.allows(capability, isEffectiveOwner: false),
        isFalse,
        reason: '$capability should deny staff',
      );
    }
  });

  test('PIN reauth only for mutate-sensitive capabilities', () {
    final needPin = {
      OwnerCapability.branches,
      OwnerCapability.staffAccounts,
      OwnerCapability.settingsSensitive,
    };
    for (final capability in OwnerCapability.values) {
      expect(
        policy.requiresPinReauth(capability),
        needPin.contains(capability),
        reason: '$capability PIN requirement mismatch',
      );
    }
  });

  group('grantedCapabilities (owner-granted per-staff-member permissions)', () {
    test('a staff member with no grants is denied every capability, exactly '
        'the pre-permissions-feature behavior', () {
      for (final capability in OwnerCapability.values) {
        expect(
          policy.allows(capability, isEffectiveOwner: false),
          isFalse,
          reason: '$capability should stay denied with no grants',
        );
      }
    });

    test('a staff member is allowed only the specific capability granted to '
        'them, not others', () {
      final granted = {OwnerCapability.inventoryEdit};
      expect(
        policy.allows(
          OwnerCapability.inventoryEdit,
          isEffectiveOwner: false,
          grantedCapabilities: granted,
        ),
        isTrue,
      );
      expect(
        policy.allows(
          OwnerCapability.branches,
          isEffectiveOwner: false,
          grantedCapabilities: granted,
        ),
        isFalse,
      );
    });

    test('the owner is always allowed regardless of grantedCapabilities '
        '(grants are a staff-only concept)', () {
      for (final capability in OwnerCapability.values) {
        expect(
          policy.allows(
            capability,
            isEffectiveOwner: true,
            grantedCapabilities: const {},
          ),
          isTrue,
        );
      }
    });
  });
}
