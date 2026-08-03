import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../data/repositories/settings_repository.dart';
import '../license/license_model.dart';
import '../license/license_repository.dart';
import '../license/license_status.dart';

/// Result of an account action (create shop login / invite staff), mirroring
/// the shape of [ActivationResult] in `license_model.dart` but kept local
/// since these actions don't produce a [CachedLicense].
class AccountActionResult {
  final bool ok;
  final String? error;
  final String? userId;
  const AccountActionResult.success(this.userId)
      : ok = true,
        error = null;
  const AccountActionResult.failure(this.error)
      : ok = false,
        userId = null;
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
  AccountRepository(this._licenseRepository, this._settings);

  final LicenseRepository _licenseRepository;
  final SettingsRepository _settings;

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

  /// Signs in with a real account, then — if this device doesn't already
  /// have a bound license — claims a device slot and activates it, so a
  /// device reached via real login still consumes the shop's device-slot
  /// limit exactly like device-key activation does.
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

    // Only claim a NEW device slot if this device isn't already activated —
    // requestDeviceSlot() has no way to know "this caller's device already
    // has one," it would just claim another slot every time it's called.
    final alreadyActivated = await _licenseRepository.current() != null;
    if (!alreadyActivated) {
      final slot = await _licenseRepository.requestDeviceSlot();
      if (slot.ok && slot.key != null) {
        await _licenseRepository.activate(slot.key!);
      }
      // A declined/failed slot claim (e.g. payment_required) still leaves
      // sign-in itself successful — the owner can retry claiming a device
      // slot from the existing Devices screen afterward.
    }
    return const AccountActionResult.success(null);
  }

  Future<void> signOut() => Supabase.instance.client.auth.signOut();

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
