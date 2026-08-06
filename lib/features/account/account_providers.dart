import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import 'account_repository.dart';

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(
    ref.watch(licenseRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(databaseProvider),
    onShopDbSwap: (toShopId) async {
      final session = ref.read(databaseSessionProvider);
      await session?.reopenForShop(toShopId);
    },
  );
});

/// Current backend account role from Supabase auth metadata, if signed in via
/// a real login. Null when signed out / anonymous.
final backendAccountRoleProvider = Provider<String?>((ref) {
  try {
    return ref.watch(accountRepositoryProvider).currentAccountRole;
  } catch (_) {
    // Supabase may be uninitialized in unit/widget tests that don't touch
    // backend auth. Treat as anonymous/no-role in that case.
    return null;
  }
});
