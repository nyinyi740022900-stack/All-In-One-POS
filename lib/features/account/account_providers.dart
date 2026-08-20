import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import 'account_repository.dart';
import 'saved_login_store.dart';

final savedLoginStoreProvider = Provider<SavedLoginStore>((ref) {
  return SavedLoginStore();
});

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(
    ref.watch(licenseRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(databaseProvider),
    onShopDbSwap: (toShopId) async {
      final session = ref.read(databaseSessionProvider);
      await session?.reopenForShop(toShopId);
    },
    onShopPromoted: (fromShopId, toShopId) async {
      final session = ref.read(databaseSessionProvider);
      await session?.reopenForShopPromotedFrom(
        fromShopId: fromShopId,
        toShopId: toShopId,
      );
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

/// Whether this device currently has a real (email) account session — the
/// replacement for the old permanent "Online mode" flag: cloud-capable UI
/// (Shop Login, Staff accounts, Branches, ...) now gates on *actually having
/// a session* rather than a device-wide mode chosen once at onboarding.
/// `AccountRepository.isSignedInWithRealAccount` is a plain getter, not
/// itself Riverpod-reactive, so every call site that changes the session
/// (sign in/out, wipe-and-claim) must `ref.invalidate` this alongside
/// [backendAccountRoleProvider] — see `shop_login_screen.dart` and
/// `daily_gate.dart` for the existing invalidation sites.
final hasRealAccountSessionProvider = Provider<bool>((ref) {
  try {
    return ref.watch(accountRepositoryProvider).isSignedInWithRealAccount;
  } catch (_) {
    return false;
  }
});
