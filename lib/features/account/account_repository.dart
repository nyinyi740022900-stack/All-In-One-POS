import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../data/local/database.dart';
import '../../data/local/shop_data_transition_service.dart';
import '../../data/repositories/settings_repository.dart';
import '../license/invoke_error.dart';
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
  const StaffAccount({
    required this.userId,
    required this.email,
    required this.banned,
  });
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
  AccountRepository(
    this._licenseRepository,
    this._settings,
    this._db, {
    this.onShopDbSwap,
    this.onShopPromoted,
  });

  final LicenseRepository _licenseRepository;
  final SettingsRepository _settings;
  final AppDatabase _db;
  late final ShopDataTransitionService _transition = ShopDataTransitionService(
    _db,
  );

  /// See [BranchRepository.onShopDbSwap]. Account wipe-and-claim opens the
  /// target shop file and leaves other shops' SQLite files on disk.
  final Future<void> Function(String toShopId)? onShopDbSwap;

  /// Like [onShopDbSwap], but for a Free-plan shop being promoted to a real
  /// one (see [_promoteFreeShopIfNeeded]) — the target file's data must
  /// travel with it from [fromShopId], not open an empty file at the new id.
  final Future<void> Function(String fromShopId, String toShopId)?
  onShopPromoted;

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
  ///   account) — reopen that account's shop SQLite file (legacy mode:
  ///   wipe the shared DB) after the same outbox safety check as a
  ///   branch switch, then claim a slot under the new shop.
  Future<AccountActionResult> signInAndClaimDevice(
    String email,
    String password,
  ) async {
    if (!Env.hasBackend) {
      return const AccountActionResult.failure('no_backend');
    }
    try {
      final authRes = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (authRes.session == null) {
        return const AccountActionResult.failure('auth_failed');
      }
    } on AuthException catch (e) {
      return AccountActionResult.failure(_authFailureCode(e));
    } catch (_) {
      return const AccountActionResult.failure('network_error');
    }

    final shopId =
        Supabase.instance.client.auth.currentUser?.appMetadata['shop_id']
            as String?;
    final currentLic = await _licenseRepository.current();

    // Same cloud shop already on this device — pull the current plan so a
    // reinstall / Check-for-renewal isn't required to see Premium.
    if (shopId != null &&
        currentLic != null &&
        currentLic.shopId == shopId &&
        !isReplaceableLocalLicense(currentLic)) {
      return _attachAccountLicense(fallback: currentLic);
    }

    // A real *other* shop is on this device. Onboarding's local Free
    // identity (`free-…`) is not a real shop — skip the wipe dialog.
    if (!isReplaceableLocalLicense(currentLic) &&
        shopId != null &&
        currentLic!.shopId != shopId) {
      return const AccountActionResult.needsWipeConfirmation();
    }

    return _finishSignInAttach();
  }

  /// Call only after the caller has shown the wipe-confirmation dialog
  /// prompted by [signInAndClaimDevice] returning
  /// [AccountActionResult.needsWipeConfirmation] and the user accepted.
  /// Legacy: wipes the shared DB. Per-shop cutover: reopens the account's
  /// shop file (other shops' files are kept). Never while unsynced writes
  /// exist on the *current* shop DB.
  Future<AccountActionResult> confirmWipeAndClaimDevice() async {
    final clearGuard = await _transition.assertSafeToClear();
    if (clearGuard != null) {
      if (clearGuard == 'stuck_outbox') {
        return const AccountActionResult.failure('stuck_outbox');
      }
      return const AccountActionResult.failure('pending_sync');
    }
    final currentLic = await _licenseRepository.current();
    final targetShopId =
        Supabase.instance.client.auth.currentUser?.appMetadata['shop_id']
            as String? ??
        '';
    if (targetShopId.isEmpty) {
      // JWT may not have shop_id yet; attaching will recover it.
      return _finishSignInAttach();
    }
    final prep = await _transition.prepareShopSwitch(
      fromShopId: currentLic?.shopId ?? '',
      toShopId: targetShopId,
    );
    if (!prep.usedWipeFallback && targetShopId.isNotEmpty) {
      await onShopDbSwap?.call(targetShopId);
    }
    return _finishSignInAttach();
  }

  Future<AccountActionResult> _finishSignInAttach() async {
    final result = await _attachAccountLicense();
    if (!result.ok) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    }
    return result;
  }

  /// Online Premium is account-tied: pull plan/expiry first. Claiming an
  /// extra device slot is only the fallback when this shop has no license
  /// row at all (so Check for renewal and a new-phone sign-in no longer
  /// fail just because every slot is already bound).
  Future<AccountActionResult> _attachAccountLicense({
    CachedLicense? fallback,
  }) async {
    final pulled = await _licenseRepository.refreshAccountLicense();
    if (pulled.ok && pulled.license != null) {
      return AccountActionResult.success(null, license: pulled.license);
    }
    if (fallback != null &&
        (pulled.errorCode == 'network_error' ||
            pulled.errorCode == 'server_error')) {
      return AccountActionResult.success(null, license: fallback);
    }
    if (pulled.errorCode == 'not_found' ||
        pulled.errorCode == 'not_activated') {
      final claimed = await _claimDeviceSlot();
      if (claimed.ok) return claimed;
    }
    return AccountActionResult.failure(
      pulled.errorCode ?? 'server_error',
    );
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

  static String _authFailureCode(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login') ||
        msg.contains('invalid_credentials') ||
        msg.contains('invalid email or password') ||
        msg.contains('user not found') ||
        msg.contains('email not found')) {
      return 'invalid_credentials';
    }
    return 'auth_failed';
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
    // Capture before the session is cleared — after sign-out,
    // currentAccountRole is null and Settings would otherwise treat this
    // device as Owner (local PIN role defaults to owner).
    final signedOutRole = currentAccountRole;
    final current = await _licenseRepository.current();
    final shopId = current?.shopId;
    CachedLicense? downgraded;
    if (current != null &&
        current.tier == 'online' &&
        current.plan != LicensePlan.free) {
      await _licenseRepository.releaseDevice(current.deviceId); // best-effort
      downgraded = await _licenseRepository.downgradeToFree(current);
    }
    await Supabase.instance.client.auth.signOut();
    if (signedOutRole == 'staff' && shopId != null && shopId.isNotEmpty) {
      await _settings.setStaffRole(shopId, 'staff');
    }
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
      final res = await invokeActivate({'action': 'set_tier', 'tier': tier});
      data = res.data as Map<String, dynamic>;
    } catch (_) {
      return const AccountActionResult.failure('network_error');
    }
    if (data['ok'] != true) {
      return AccountActionResult.failure(data['error'] as String?);
    }
    final current = await _licenseRepository.current();
    if (current == null) {
      return const AccountActionResult.failure('not_activated');
    }
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
    String shopName,
    String email,
    String password,
  ) async {
    if (!Env.hasBackend) return const SignupResult.failure('no_backend');
    final deviceId = await _settings.deviceId();

    Map<String, dynamic> data;
    try {
      final res = await invokeActivate({
        'action': 'signup_shop',
        'shop_name': shopName,
        'email': email,
        'password': password,
        'device_id': deviceId,
      });
      final parsed = parseInvokeData(res.data);
      if (parsed == null) return const SignupResult.failure('server_error');
      data = parsed;
    } catch (e) {
      return SignupResult.failure(classifyInvokeError(e));
    }
    if (data['ok'] != true) {
      return SignupResult.failure(data['error'] as String?);
    }
    final expiresAtRaw = data['expires_at'] as String?;
    if (expiresAtRaw == null) return const SignupResult.failure('server_error');

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (e) {
      return SignupResult.failure(_authFailureCode(e));
    } catch (_) {
      return const SignupResult.failure('network_error');
    }

    final now = DateTime.now();
    final lic = CachedLicense(
      key: 'SIGNUP',
      shopId: data['shop_id'] as String,
      plan: LicensePlan.trial,
      expiresAt: DateTime.parse(expiresAtRaw),
      activatedAt:
          DateTime.tryParse(data['activated_at'] as String? ?? '') ?? now,
      lastVerifiedAt: now,
      deviceId: deviceId,
      tier: data['tier'] as String? ?? 'online',
    );
    await _promoteFreeShopIfNeeded(lic.shopId);
    await _licenseRepository.saveExternal(lic);
    return SignupResult.success(lic);
  }

  /// A Free-plan shop (`shop_id = free-<deviceId>`, purely local — see
  /// `sync_providers.dart`'s `syncEngineProvider`) has no server-side
  /// presence. [signupShop] mints a real, server-assigned shop distinct from
  /// the local one — without this, the caller's subsequent `applyExternal`
  /// would leave the device pointed at a brand-new, empty shop file and
  /// silently strand every local sale/product behind the old Free identity.
  /// Moves the data to travel with it instead. Same reasoning as
  /// `LicenseController._promoteFreeShopIfNeeded`, for the "create a shop
  /// via email" path instead of "activate a key."
  Future<void> _promoteFreeShopIfNeeded(String toShopId) async {
    final current = await _licenseRepository.current();
    if (current == null ||
        current.plan != LicensePlan.free ||
        current.shopId == toShopId ||
        !AppDatabase.usePerShopDbFiles) {
      return;
    }
    final fromShopId = current.shopId;
    // Written before the data rewrite starts, cleared only after the file
    // rename succeeds — see `resolvePendingShopPromotion` for how a crash
    // mid-promotion is resumed on next launch.
    await _settings.setPendingShopPromotion(fromShopId, toShopId);
    await _transition.promoteShopIdentity(
      fromShopId: fromShopId,
      toShopId: toShopId,
    );
    await onShopPromoted?.call(fromShopId, toShopId);
    await _settings.clearPendingShopPromotion();
  }

  Future<AccountActionResult> createShopLogin(
    String email,
    String password,
  ) async {
    if (!Env.hasBackend) {
      return const AccountActionResult.failure('no_backend');
    }
    try {
      final res = await invokeActivate({
        'action': 'create_shop_login',
        'email': email,
        'password': password,
      });
      final data = parseInvokeData(res.data);
      if (data == null) {
        return const AccountActionResult.failure('server_error');
      }
      if (data['ok'] == true) {
        // A real email/password login is the definition of "Online" — the
        // License screen's Renew/Upgrade dialog picks Offline vs Online by
        // tier, so a shop that just gained a login but stayed tier 'offline'
        // would confusingly still see the key-based dialog. Auto-switch;
        // best-effort (a failure here doesn't fail the login itself, which
        // already succeeded server-side, and the owner can still switch
        // manually via Settings → Pricing tier).
        final current = await _licenseRepository.current();
        CachedLicense? updated;
        if (current != null && current.tier != 'online') {
          final tierResult = await setPricingTier('online');
          if (tierResult.ok) updated = tierResult.license;
        }
        return AccountActionResult.success(
          data['user_id'] as String?,
          license: updated,
        );
      }
      return AccountActionResult.failure(data['error'] as String?);
    } catch (e) {
      return AccountActionResult.failure(classifyInvokeError(e));
    }
  }

  Future<AccountActionResult> inviteStaff(String email, String password) async {
    if (!Env.hasBackend) {
      return const AccountActionResult.failure('no_backend');
    }
    try {
      final res = await invokeActivate({
        'action': 'invite_staff',
        'email': email,
        'password': password,
      });
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
      final res = await invokeActivate({'action': 'list_staff'});
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) return const [];
      final staff = (data['staff'] as List).cast<Map<String, dynamic>>();
      return staff
          .map(
            (s) => StaffAccount(
              userId: s['user_id'] as String,
              email: s['email'] as String? ?? '',
              banned: s['banned'] as bool? ?? false,
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> revokeStaff(String userId) async {
    if (!Env.hasBackend) return false;
    try {
      final res = await invokeActivate({
        'action': 'revoke_staff',
        'user_id': userId,
      });
      final data = res.data as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Permanently deletes the signed-in owner's online account (and owned
  /// shops' cloud data). Caller must pass the account password. On success
  /// the local device should wipe shop data and enter Free plan.
  Future<AccountActionResult> deleteAccount(String password) async {
    if (!Env.hasBackend) {
      return const AccountActionResult.failure('no_backend');
    }
    if (!isSignedInWithRealAccount) {
      return const AccountActionResult.failure('not_authenticated');
    }
    if (currentAccountRole != 'owner') {
      return const AccountActionResult.failure('forbidden');
    }
    try {
      final res = await invokeActivate({
        'action': 'delete_account',
        'password': password,
      });
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) {
        return AccountActionResult.failure(data['error'] as String?);
      }
      // Auth user is gone — local sign-out may fail; ignore.
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      return const AccountActionResult.success(null);
    } catch (_) {
      return const AccountActionResult.failure('network_error');
    }
  }
}
