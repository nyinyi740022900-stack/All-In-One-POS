import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/account/account_providers.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';

void main() {
  group('settings permission matrix (effective role)', () {
    ProviderContainer container({
      String? backendRole,
    }) {
      return ProviderContainer(
        overrides: [
          backendAccountRoleProvider.overrideWithValue(backendRole),
        ],
      );
    }

    test('owner when backend role is absent', () async {
      final c = container();
      addTearDown(c.dispose);
      expect(c.read(isEffectiveOwnerProvider), isTrue);
      expect(c.read(canEditInventoryProvider), isTrue);
    });

    test('staff when backend role is staff', () async {
      final c = container(backendRole: 'staff');
      addTearDown(c.dispose);
      expect(c.read(isEffectiveOwnerProvider), isFalse);
      expect(c.read(canEditInventoryProvider), isFalse);
    });

    test('owner when backend role is owner', () async {
      final c = container(backendRole: 'owner');
      addTearDown(c.dispose);
      expect(c.read(isEffectiveOwnerProvider), isTrue);
      expect(c.read(canEditInventoryProvider), isTrue);
    });

    test('unknown backend role is treated as staff-safe fallback', () async {
      final c = container(backendRole: 'admin');
      addTearDown(c.dispose);
      expect(c.read(isEffectiveOwnerProvider), isFalse);
    });
  });
}
