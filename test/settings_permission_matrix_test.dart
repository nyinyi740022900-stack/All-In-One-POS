import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/account/account_providers.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';

void main() {
  group('settings permission matrix (effective role)', () {
    ProviderContainer container({
      required String localRole,
      String? backendRole,
    }) {
      return ProviderContainer(
        overrides: [
          staffRoleProvider.overrideWith((ref) => Stream.value(localRole)),
          backendAccountRoleProvider.overrideWithValue(backendRole),
        ],
      );
    }

    test('owner when local=owner and backend role is absent', () async {
      final c = container(localRole: 'owner');
      addTearDown(c.dispose);
      await c.read(staffRoleProvider.future);
      expect(c.read(isEffectiveOwnerProvider), isTrue);
      expect(c.read(canEditInventoryProvider), isTrue);
    });

    test('staff when local=staff and backend role is absent', () async {
      final c = container(localRole: 'staff');
      addTearDown(c.dispose);
      await c.read(staffRoleProvider.future);
      expect(c.read(isEffectiveOwnerProvider), isFalse);
      expect(c.read(canEditInventoryProvider), isFalse);
    });

    test('backend staff overrides local owner (most restrictive wins)',
        () async {
      final c = container(localRole: 'owner', backendRole: 'staff');
      addTearDown(c.dispose);
      await c.read(staffRoleProvider.future);
      expect(c.read(isEffectiveOwnerProvider), isFalse);
      expect(c.read(canEditInventoryProvider), isFalse);
    });

    test('backend owner still follows local device mode', () async {
      final owner = container(localRole: 'owner', backendRole: 'owner');
      addTearDown(owner.dispose);
      await owner.read(staffRoleProvider.future);
      expect(owner.read(isEffectiveOwnerProvider), isTrue);

      final staff = container(localRole: 'staff', backendRole: 'owner');
      addTearDown(staff.dispose);
      await staff.read(staffRoleProvider.future);
      expect(staff.read(isEffectiveOwnerProvider), isFalse);
    });

    test('unknown backend role is treated as staff-safe fallback', () async {
      final c = container(localRole: 'owner', backendRole: 'admin');
      addTearDown(c.dispose);
      await c.read(staffRoleProvider.future);
      expect(c.read(isEffectiveOwnerProvider), isFalse);
    });
  });
}
