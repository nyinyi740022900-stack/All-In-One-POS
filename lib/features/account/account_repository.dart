import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../data/local/database.dart';
import '../../data/repositories/settings_repository.dart';
import '../license/license_model.dart';
import '../license/license_repository.dart';
import '../license/license_status.dart';

/// Result of an account action (create shop login / invite staff / sign in),
/// mirroring the shape of [ActivationResult] in `license_model.dart`. Most
/// actions never populate [license] — only [AccountRepository.signInAndClaimDevice]
/// does, so the caller can apply it via `LicenseController.applyExternal`.
class AccountActionResult {
  final bool ok;
  final String? error;
  final String? userId;
  final CachedLicense? license;
  final bool needsWipeConfirmation;
  const AccountActionResult.success(this.userId, {this.license})
      : ok = true,
        error = null,
        needsWipeConfirmation = false;
  const AccountActionResult.failure(this.error)
      : ok = false,
        userId = null,
        license = null,
        needsWipeConfirmation = false;
  // Signed in successfully, but this device was previously scoped to a
  // DIFFERENT shop — proceeding would wipe local data. The caller must show
  // an explicit confirmation and, if accepted, call
  // [AccountRepository.confirmWipeAndClaimDevice]; if declined, sign back out
  // rather than leaving the device mid-session for a shop its local data
  // doesn't match.
  const AccountActionResult.needsWipeConfirmation()
      : ok = false,
        error = null,
        userId = null,
        license = null,
        needsWipeConfirmation = true;
}

/// Outcome of [AccountRepository.signupShop] — carries the freshly-minted
/// [CachedLicense] on success so the caller can apply it via
/// `LicenseController.applyExternal` (same pattern as a branch switch).
class SignupResult {
  final bool ok;
  final String? error;
  final CachedLicense? license;
  const SignupResult.success(this.license) : ok = true, error = null;
  const SignupResult.failure(this.error) : ok = false, license = null;
}

/// One invited staff account, as returned by listing `auth.users` for this
/// shop (see [AccountRepository.listStaffAccounts]).
class StaffAccount {
  final String userId;
  final String email;
  final bool banned;
  const StaffAccount(
      {required this.userId, required this.email, required this.banned});
}

/// Real email/password login for a shop's owner and staff — additive to the
/// existing device-key activation + local PIN roster (`staff_repository.dart`),
/// which are completely unaffected by this. See `activate` Edge Function's
/// `create_shop_login`/`invite_staff`/`revoke_staff` actions for the
/// server-side half of this.
///
/// A device that signs in with a real account still needs its own device
/// slot the same way a key-activated device does — [signInAndClaimDevice]
/// chains the existing [LicenseRepository.requestDeviceSlot]/`activate` calls
/// after a successful password sign-in, reusing that machinery as-is rather
/// than duplicating it.
class AccountRepository {
  AccountRepository(this._licenseRepository, this._settings, this._db);

  final LicenseRepository _licenseRepository;
  final SettingsRepository _settings;
  final AppDatabase _db;

  bool get isSignedInWithRealAccount {
    final user = Supabase.instance.client.auth.currentUser;
    // An anonymous session's user also exists but has no email — that's the
    // device-key path, not a real account.
    return user != null && (user.email ?? '').isNotEmpty;
  }

  String? get currentAccountEmail =>
      Supabase.instance.client.auth.currentUser?.email;

  String? get currentAccountRole {
    final meta = Supabase.instance.client.auth.currentUser?.appMetadata;
    final role = meta?['role'];
    return role is String && role.isNotEmpty ? role : null;
  }

  /// Signs in with a real account, then makes sure THIS device ends up
  /// correctly scoped to the account's own shop_id — the caller must apply
  /// the returned [AccountActionResult.license] via
  /// `LicenseController.applyExternal` and kick `SyncController.sync()`
  /// afterward (this repository stays Riverpod-free, same split as
  /// `BranchRepository.switchBranch`).
  ///
  /// Three cases:
  /// - This device already has no cached license (brand new / never
  ///   activated) — claims a device slot under the account's shop and
  ///   activates it, consuming the shop's device-slot limit exactly like
  ///   device-key activation does.
  /// - This device is already correctly scoped to the SAME shop (e.g.
  ///   re-signing in after a sign-out) — nothing to claim or resync.
  /// - This device was previously activated for a DIFFERENT shop (e.g. a
  ///   device-key-activated shop's owner signing into a different real
  ///   account) — the local DB isn't partitioned per shop, so it must be
  ///   wiped (same safety check as a branch switch: never while unsynced
  ///   writes exist) before claiming a slot under the new shop.
  Future<AccountActionResult> signInAndClaimDevice(
      String email, String password) async {
    if (!Env.hasBackend) {
      return const AccountActionResult.failure('no_backend');
    }
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      return AccountActionResult.failure(e.message);
    } catch (_) {
      return const AccountActionResult.failure('network_error');
    }

    final shopId =
        Supabase.instance.client.auth.currentUser?.appMetadata['shop_id']
            as String?;
    if (shopId == null) return const AccountActionResult.failure('not_activated');

    final currentLic = await _licenseRepository.current();
    if (currentLic != null && currentLic.shopId == shopId) {
      return AccountActionResult.success(null, license: currentLic);
    }

    if (currentLic != null) {
      // Scoped to a different shop already — don't wipe without the caller
      // showing an explicit confirmation first.
      return const AccountActionResult.needsWipeConfirmation();
    }

    return _claimDeviceSlot();
  }

  /// Call only after the caller has shown the wipe-confirmation dialog
  /// prompted by [signInAndClaimDevice] returning
  /// [AccountActionResult.needsWipeConfirmation] and the user accepted.
  /// Wipes local data (same safety check as a branch switch: never while
  /// unsynced writes exist) then claims a device slot under the now-signed-in
  /// account's shop.
  Future<AccountActionResult> confirmWipeAndClaimDevice() async {
    final pending = await _db.select(_db.outbox).get();
    if (pending.isNotEmpty) {
      return const AccountActionResult.failure('pending_sync');
    }
    await _db.wipeSyncedData();
    return _claimDeviceSlot();
  }

  Future<AccountActionResult> _claimDeviceSlot() async {
    final slot = await _licenseRepository.requestDeviceSlot();
    if (!slot.ok || slot.key == null) {
      return AccountActionResult.failure(slot.errorCode ?? 'server_error');
    }
    final result = await _licenseRepository.activate(slot.key!);
    if (!result.ok) return AccountActionResult.failure(result.errorCode);
    return AccountActionResult.success(null, license: result.license);
  }

  /// Signs out of the real-login session. On an Online-tier shop, Premium is
  /// tied to being an authenticated, paying, signed-in user — not to the
  /// device having once claimed a slot — so signing out also releases this
  /// device's slot and downgrades it to the Free plan (Sell/Inventory keep
  /// working, Premium features lock until signing back in). This does NOT
  /// apply when `tier == 'offline'`: that device's Premium comes from its own
  /// key, independent of any auth session (e.g. an owner's permanent
  /// register that also has a real-login layered on top) — signing out of
  /// the account there is unaffected, exactly as the sign-out confirmation
  /// dialog already tells the owner.
  Future<AccountActionResult> signOut() async {
    final current = await _licenseRepository.current();
    CachedLicense? downgraded;
    if (current != null &&
        current.tier == 'online' &&
        current.plan != LicensePlan.free) {
      await _licenseRepository.releaseDevice(current.deviceId); // best-effort
      downgraded = await _licenseRepository.downgradeToFree(current);
    }
    await Supabase.instance.client.auth.signOut();
    return AccountActionResult.success(null, license: downgraded);
  }

  /// Self-service switches the shop's pricing tier ('offline'/'online') —
  /// affects only the *suggested* price on the next renewal request, never
  /// `shopId`/session/local data, so no wipe/resync is needed. The caller
  /// applies the returned [AccountActionResult.license] via
  /// `LicenseController.applyExternal`.
  Future<AccountActionResult> setPricingTier(String tier) async {
    if (!Env.hasBackend) return const AccountActionResult.failure('no_backend');
    Map<String, dynamic> data;
    try {
      final res = await Supabase.instance.client.functions
          .invoke('activate', body: {'action': 'set_tier', 'tier': tier});
      data = res.data as Map<String, dynamic>;
    } catch (_) {
      return const AccountActionResult.failure('network_error');
    }
    if (data['ok'] != true) {
      return AccountActionResult.failure(data['error'] as String?);
    }
    final current = await _licenseRepository.current();
    if (current == null) return const AccountActionResult.failure('not_activated');
    final updated = current.copyWith(tier: tier);
    await _licenseRepository.saveExternal(updated);
    return AccountActionResult.success(null, license: updated);
  }

  /// Mints a brand new shop from nothing (no prior device-key activation
  /// needed) — the entry point for the "Online" onboarding path: a shop
  /// name + email + password gets a fresh shop_id, a 2-month trial license
  /// bound to this device, and a real owner login, all in one call
  /// (`signup_shop`). Signs in with the new credentials directly afterward
  /// (no `refreshSession()` dance — a fresh sign-in already carries the
  /// right claims) and builds the resulting [CachedLicense] for the caller
  /// to apply via `LicenseController.applyExternal`.
  Future<SignupResult> signupShop(
      String shopName, String email, String password) async {
    if (!Env.hasBackend) return const SignupResult.failure('no_backend');
    final deviceId = await _settings.deviceId();

    Map<String, dynamic> data;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {
          'action': 'signup_shop',
          'shop_name': shopName,
          'email': email,
          'password': password,
          'device_id': deviceId,
        },
      );
      data = res.data as Map<String, dynamic>;
    } catch (_) {
      return const SignupResult.failure('network_error');
    }
    if (data['ok'] != true) {
      return SignupResult.failure(data['error'] as String?);
    }
    final expiresAtRaw = data['expires_at'] as String?;
    if (expiresAtRaw == null) return const SignupResult.failure('server_error');

    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      return SignupResult.failure(e.message);
    } catch (_) {
      return const SignupResult.failure('network_error');
    }

    final now = DateTime.now();
    final lic = CachedLicense(
      key: 'SIGNUP',
      shopId: data['shop_id'] as String,
      plan: LicensePlan.trial,
      expiresAt: DateTime.parse(expiresAtRaw),
      activatedAt: DateTime.tryParse(data['activated_at'] as String? ?? '') ?? now,
      lastVerifiedAt: now,
      deviceId: deviceId,
      tier: data['tier'] as String? ?? 'online',
    );
    await _licenseRepository.saveExternal(lic);
    return SignupResult.success(lic);
  }

  Future<AccountActionResult> createShopLogin(
      String email, String password) async {
    if (!Env.hasBackend) {
      return const AccountActionResult.failure('no_backend');
    }
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {
          'action': 'create_shop_login',
          'email': email,
          'password': password,
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] == true) {
        return AccountActionResult.success(data['user_id'] as String?);
      }
      return AccountActionResult.failure(data['error'] as String?);
    } catch (_) {
      return const AccountActionResult.failure('network_error');
    }
  }

  Future<AccountActionResult> inviteStaff(
      String email, String password) async {
    if (!Env.hasBackend) {
      return const AccountActionResult.failure('no_backend');
    }
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {
          'action': 'invite_staff',
          'email': email,
          'password': password,
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] == true) {
        return AccountActionResult.success(data['user_id'] as String?);
      }
      return AccountActionResult.failure(data['error'] as String?);
    } catch (_) {
      return const AccountActionResult.failure('network_error');
    }
  }

  Future<List<StaffAccount>> listStaffAccounts() async {
    if (!Env.hasBackend) return const [];
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {'action': 'list_staff'},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) return const [];
      final staff = (data['staff'] as List).cast<Map<String, dynamic>>();
      return staff
          .map((s) => StaffAccount(
                userId: s['user_id'] as String,
                email: s['email'] as String? ?? '',
                banned: s['banned'] as bool? ?? false,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> revokeStaff(String userId) async {
    if (!Env.hasBackend) return false;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {'action': 'revoke_staff', 'user_id': userId},
      );
      final data = res.data as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
