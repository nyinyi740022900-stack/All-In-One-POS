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
      OwnerCapability.syncIssuesDiscard,
    };
    for (final capability in OwnerCapability.values) {
      expect(
        policy.requiresPinReauth(capability),
        needPin.contains(capability),
        reason: '$capability PIN requirement mismatch',
      );
    }
  });
}
