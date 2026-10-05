import 'package:supabase_flutter/supabase_flutter.dart';

import 'social_auth.dart';
import 'account_identity_policy.dart';
import 'owner_email_transport.dart';

import '../../core/env.dart';
import '../../data/local/database.dart';
import '../../data/local/shop_data_transition_service.dart';
import '../../data/repositories/settings_repository.dart';
import '../license/invoke_error.dart';
import '../license/license_model.dart';
import '../license/license_repository.dart';
import '../license/license_status.dart';

/// The two phases of [AccountRepository.signInAndClaimDevice] worth telling
/// the user apart: checking the password, then finding and attaching the
/// shop. Deliberately only two — those are the real network boundaries, and
/// inventing more would be a progress bar that lies.
enum SignInStep { authenticating, openingShop }

typedef SignInStepCallback = void Function(SignInStep step);

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
  final bool needsShopName;
  const AccountActionResult.success(this.userId, {this.license})
    : ok = true,
      error = null,
      needsWipeConfirmation = false,
      needsShopName = false;
  const AccountActionResult.failure(this.error)
    : ok = false,
      userId = null,
      license = null,
      needsWipeConfirmation = false,
      needsShopName = false;
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
      needsWipeConfirmation = true,
      needsShopName = false;
  const AccountActionResult.needsShopName()
    : ok = false,
      error = null,
      userId = null,
      license = null,
      needsWipeConfirmation = false,
      needsShopName = true;
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

/// Account authentication, explicit device provisioning and safe shop attachment.
class AccountRepository {
  AccountRepository(
    this._licenseRepository,
    this._settings,
    this._db, {
    this.onShopDbSwap,
    this.onShopPromoted,
    // Keep the public injection name independent of private lazy storage.
    SocialAuthService? socialAuth,
    // ignore: prefer_initializing_formals
  }) : _socialAuth = socialAuth;

  SocialAuthService? _socialAuth;
  SocialAuthService get socialAuth => _socialAuth ??= SocialAuthService();

  User? get currentAuthUser {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  Set<SocialAuthProvider> get availableSocialProviders =>
      socialAuth.availableProviders;
  Set<SocialAuthProvider> get linkedSocialProviders => {
    for (final identity in currentAuthUser?.identities ?? <UserIdentity>[])
      for (final provider in SocialAuthProvider.values)
        if (identity.provider == provider.name) provider,
  };
  bool get hasPasswordIdentity =>
      isSignedInWithRealAccount &&
      ((currentAuthUser?.identities ?? <UserIdentity>[]).any(
            (i) => i.provider == 'email',
          ) ||
          ((currentAuthUser?.identities ?? <UserIdentity>[]).isEmpty &&
              linkedSocialProviders.isEmpty));

  Future<Map<String, dynamic>?> invokeSocialAction(
    Map<String, dynamic> body,
  ) async => parseInvokeData((await invokeActivate(body)).data);
  Future<void> refreshAuthenticatedSession() => refreshSessionBounded();

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
    final user = currentAuthUser;
    // An anonymous session's user also exists but has no email — that's the
    // device-key path, not a real account.
    return user != null && !user.isAnonymous && (user.email ?? '').isNotEmpty;
  }

  String? get currentAccountEmail => currentAuthUser?.email;

  String? get currentAccountRole {
    final meta = currentAuthUser?.appMetadata;
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
  ///
  /// [onStep] reports the two real phases so the caller can say which one is
  /// running instead of showing one undifferentiated spinner — same shape as
  /// [BranchSwitchStepCallback]. The boundary is honest: [SignInStep.openingShop]
  /// fires only once the password has actually been accepted.
  Future<AccountActionResult> signInAndClaimDevice(
    String email,
    String password, {
    SignInStepCallback? onStep,
  }) async {
    if (!Env.hasBackend) {
      return const AccountActionResult.failure('no_backend');
    }
    _licenseRepository.cancelPendingRequests();
    onStep?.call(SignInStep.authenticating);
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

    // Password accepted from here on — everything below is finding and
    // attaching the shop, which is a different (and usually longer) wait.
    onStep?.call(SignInStep.openingShop);

    return _completeAuthenticatedSignIn();
  }

  Future<AccountActionResult> _completeAuthenticatedSignIn() async {
    final shopId = currentAuthUser?.appMetadata['shop_id'] as String?;
    final currentLic = await _licenseRepository.current();

    // Same cloud shop already on this device — pull the current plan so a
    // reinstall / Check-for-renewal isn't required to see Premium.
    if (shopId != null &&
        currentLic != null &&
        currentLic.shopId == shopId &&
        !isReplaceableLocalLicense(currentLic)) {
      return attachAccountLicense(fallback: currentLic);
    }

    // A real *other* shop is on this device. Onboarding's local Free
    // identity (`free-…`) is not a real shop — skip the wipe dialog.
    if (currentLic != null &&
        !isReplaceableLocalLicense(currentLic) &&
        shopId != null &&
        currentLic.shopId != shopId) {
      return const AccountActionResult.needsWipeConfirmation();
    }

    return _finishSignInAttach();
  }

  Future<AccountActionResult> signInWithSocial(
    SocialAuthProvider provider,
  ) async {
    if (!availableSocialProviders.contains(provider)) {
      return const AccountActionResult.failure('social_auth_unavailable');
    }
    _licenseRepository.cancelPendingRequests();
    try {
      final response = await socialAuth.signIn(provider);
      if (response.session == null || !isSignedInWithRealAccount) {
        return const AccountActionResult.failure('not_authenticated');
      }
      final data = await invokeSocialAction({
        'action': 'prepare_social_account',
      });
      if (data?['ok'] != true) {
        return AccountActionResult.failure(
          data?['error'] as String? ?? 'server_error',
        );
      }
      if (data?['needs_shop_name'] == true) {
        return const AccountActionResult.needsShopName();
      }
      return await _finishSocialAccount(data!);
    } catch (e) {
      return _socialFailure(e);
    }
  }

  Future<AccountActionResult> completeSocialSignup(String shopName) async {
    if (!isSignedInWithRealAccount) {
      return const AccountActionResult.failure('not_authenticated');
    }
    if (currentAccountRole == 'staff') {
      return const AccountActionResult.failure('forbidden');
    }
    if (shopName.trim().isEmpty) {
      return const AccountActionResult.failure('invalid_shop_name');
    }
    try {
      final data = await invokeSocialAction({
        'action': 'signup_social_shop',
        'shop_name': shopName.trim(),
        'device_id': await _settings.deviceId(),
      });
      if (data?['ok'] != true) {
        return AccountActionResult.failure(
          data?['error'] as String? ?? 'server_error',
        );
      }
      return await _finishSocialAccount(data!);
    } catch (e) {
      return _socialFailure(e);
    }
  }

  Future<AccountActionResult> _finishSocialAccount(
    Map<String, dynamic> data,
  ) async {
    await refreshAuthenticatedSession();
    final shop = data['shop_id'];
    if (shop is! String ||
        shop.isEmpty ||
        currentAuthUser?.appMetadata['shop_id'] != shop ||
        !const ['owner', 'staff'].contains(currentAccountRole)) {
      return const AccountActionResult.failure('not_authenticated');
    }
    return _completeAuthenticatedSignIn();
  }

  Future<AccountActionResult> linkSocialIdentity(
    SocialAuthProvider provider,
  ) async {
    if (!isSignedInWithRealAccount) {
      return const AccountActionResult.failure('not_authenticated');
    }
    final userId = currentAuthUser!.id;
    try {
      final response = await socialAuth.link(provider);
      if (response.user?.id != userId || currentAuthUser?.id != userId) {
        return const AccountActionResult.failure('not_authenticated');
      }
      return AccountActionResult.success(userId);
    } catch (e) {
      return _socialFailure(e);
    }
  }

  /// Requests Supabase's secure email confirmation flow. Never rewrites
  /// owner_user_id, shop membership, trial usage or Premium/device receipts.
  Future<AccountActionResult> requestOwnerEmailChange(String newEmail) async {
    if (!isSignedInWithRealAccount) {
      return const AccountActionResult.failure('not_authenticated');
    }
    if (currentAccountRole != 'owner') {
      return const AccountActionResult.failure('forbidden');
    }
    final email = newEmail.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return const AccountActionResult.failure('invalid_email');
    }
    if (email.toLowerCase() == currentAccountEmail?.trim().toLowerCase()) {
      return const AccountActionResult.failure('email_unchanged');
    }
    final id = currentAuthUser!.id;
    try {
      final updated = await updateOwnerEmail(email);
      if (updated?.id != id || currentAuthUser?.id != id) {
        return const AccountActionResult.failure('not_authenticated');
      }
      return AccountActionResult.success(id);
    } catch (e) {
      return _identityFailure(e);
    }
  }

  Future<User?> updateOwnerEmail(String email) =>
      requestOwnerEmail(Supabase.instance.client, email);

  Future<List<UserIdentity>> fetchOwnerIdentities() async {
    final user = (await Supabase.instance.client.auth.getUser().timeout(
      const Duration(seconds: 30),
    )).user;
    if (user?.id != currentAuthUser?.id) {
      throw const SocialAuthFailure('not_authenticated');
    }
    return user?.identities ?? [];
  }

  Future<void> unlinkOwnerIdentity(UserIdentity identity) => Supabase
      .instance
      .client
      .auth
      .unlinkIdentity(identity)
      .timeout(const Duration(seconds: 30));

  Future<AccountActionResult> removeOwnerGoogleIdentity(
    String identityId,
  ) async {
    if (!isSignedInWithRealAccount) {
      return const AccountActionResult.failure('not_authenticated');
    }
    if (currentAccountRole != 'owner') {
      return const AccountActionResult.failure('forbidden');
    }
    final id = currentAuthUser!.id;
    try {
      final identities = await fetchOwnerIdentities();
      if (currentAuthUser?.id != id || identities.any((i) => i.userId != id)) {
        return const AccountActionResult.failure('not_authenticated');
      }
      if (!canRemoveGoogleIdentity(identities, identityId)) {
        return const AccountActionResult.failure('last_sign_in');
      }
      final identity = identities.firstWhere((i) => i.identityId == identityId);
      await unlinkOwnerIdentity(identity);
      if (currentAuthUser?.id != id) {
        return const AccountActionResult.failure('not_authenticated');
      }
      await refreshAuthenticatedSession();
      return AccountActionResult.success(id);
    } catch (e) {
      return _identityFailure(e);
    }
  }

  AccountActionResult _identityFailure(Object e) {
    if (e is StateError) {
      return const AccountActionResult.failure('not_authenticated');
    }
    final code = e is AuthException ? e.code : null;
    return AccountActionResult.failure(switch (code) {
      'email_exists' || 'user_already_exists' => 'email_taken',
      'identity_already_exists' => 'identity_already_exists',
      'email_address_invalid' || 'validation_failed' => 'invalid_email',
      'manual_linking_disabled' => 'social_auth_unavailable',
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' => 'email_rate_limit',
      _ => _socialFailure(e).error,
    });
  }

  Future<AccountActionResult> deleteAccountWithSocial(
    SocialAuthProvider provider,
  ) async {
    if (!isSignedInWithRealAccount) {
      return const AccountActionResult.failure('not_authenticated');
    }
    if (currentAccountRole != 'owner') {
      return const AccountActionResult.failure('forbidden');
    }
    if (!linkedSocialProviders.contains(provider) ||
        !availableSocialProviders.contains(provider)) {
      return const AccountActionResult.failure('social_auth_unavailable');
    }
    try {
      final proof = await socialAuth.reauthenticate(provider);
      final data = await invokeSocialAction({
        'action': 'delete_account',
        ...proof.toRequest(),
      });
      if (data?['ok'] != true) {
        return AccountActionResult.failure(
          data?['error'] as String? ?? 'server_error',
        );
      }
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      return const AccountActionResult.success(null);
    } catch (e) {
      return _socialFailure(e);
    }
  }

  AccountActionResult _socialFailure(Object error) =>
      AccountActionResult.failure(
        error is SocialAuthFailure
            ? error.code
            : error is AuthException
            ? _authFailureCode(error)
            : classifyInvokeError(error),
      );

  /// Call only after the caller has shown the wipe-confirmation dialog
  /// prompted by [signInAndClaimDevice] returning
  /// [AccountActionResult.needsWipeConfirmation] and the user accepted.
  /// Legacy: wipes the shared DB. Per-shop cutover: reopens the account's
  /// shop file (other shops' files are kept). Never while unsynced writes
  /// exist on the *current* shop DB.
  Future<AccountActionResult> confirmWipeAndClaimDevice() async {
    final clearGuard = await _transition.assertSafeToClear();
    if (clearGuard != null) {
      // The caller already confirmed the wipe, so this device's session is
      // now authenticated as the NEW shop while local data/outbox still
      // belong to the OLD one. Sign back out (same as the decline branch in
      // the caller's dialog) rather than leaving that mismatch in place —
      // otherwise the stuck outbox this just blocked on would start getting
      // rejected by shop_isolation RLS too (JWT says the new shop, the rows
      // say the old one), making the stuck-outbox problem worse, not just
      // deferred.
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      if (clearGuard == 'stuck_outbox') {
        return const AccountActionResult.failure('stuck_outbox');
      }
      return const AccountActionResult.failure('pending_sync');
    }
    final currentLic = await _licenseRepository.current();
    // Provision first; a device-limit or network failure must not reopen/wipe
    // another shop's database or replace this device's cached identity.
    final result = await attachAccountLicense(persist: false);
    if (!result.ok || result.license == null) return result;
    final targetShopId = result.license!.shopId;
    final renewedGuard = await _transition.assertSafeToClear();
    if (renewedGuard != null) return AccountActionResult.failure(renewedGuard);
    final prep = await _transition.prepareShopSwitch(
      fromShopId: currentLic?.shopId ?? '',
      toShopId: targetShopId,
    );
    if (!prep.usedWipeFallback) await onShopDbSwap?.call(targetShopId);
    await _licenseRepository.saveExternal(result.license!);
    return result;
  }

  Future<AccountActionResult> _finishSignInAttach() async {
    final result = await attachAccountLicense(persist: false);
    if (result.ok && result.license != null) {
      await _promoteFreeShopIfNeeded(result.license!.shopId);
      await _licenseRepository.saveExternal(result.license!);
    }
    // A transient failure (offline, server hiccup — already retried once
    // inside refreshAccountLicense) doesn't mean this account/device combo
    // is unusable, just that the pull didn't land this time. Signing out
    // here would throw away a password the user already typed correctly,
    // turning a retry into a full re-login. Only sign out for failures that
    // mean this session genuinely can't attach on this device (no shop,
    // device limit, forbidden, etc.) so the app doesn't sit mid-session for
    // an account it just told the user it couldn't use.
    if (!result.ok &&
        result.error != 'network_error' &&
        result.error != 'server_error' &&
        !(const [
              'device_limit_reached',
              'free_device_replacement_required',
            ].contains(result.error) &&
            currentAccountRole == 'owner')) {
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
    }
    return result;
  }

  /// Attach a verified authenticated membership through device authority.
  Future<AccountActionResult> attachAccountLicense({
    CachedLicense? fallback,
    bool persist = true,
  }) async {
    final pulled = await _licenseRepository.refreshAccountLicense(
      reclaimDevice: true,
      persist: persist,
    );
    if (pulled.ok && pulled.license != null) {
      await _rememberLocalRole(pulled.license!.shopId);
      return AccountActionResult.success(null, license: pulled.license);
    }
    if (fallback != null &&
        (pulled.errorCode == 'network_error' ||
            pulled.errorCode == 'server_error')) {
      await _rememberLocalRole(fallback.shopId);
      return AccountActionResult.success(null, license: fallback);
    }
    return AccountActionResult.failure(pulled.errorCode ?? 'server_error');
  }

  Future<void> _rememberLocalRole(String shopId) async {
    // Only the authenticated app_metadata role is used, never user_metadata.
    // Keeping staff's floor per shop prevents auth loss becoming local Owner.
    final role = currentAccountRole;
    if (role == 'staff' || role == 'owner') {
      await _settings.setStaffRole(shopId, role!);
    }
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

  /// Remove Premium and release this device while retaining local records
  /// and the shop-scoped staff role floor.
  Future<AccountActionResult> signOut() async {
    // Capture before the session is cleared — after sign-out,
    // currentAccountRole is null and Settings would otherwise treat this
    // device as Owner (local PIN role defaults to owner).
    final signedOutRole = currentAccountRole;
    final current = await _licenseRepository.current();
    final shopId = current?.shopId;
    CachedLicense? downgraded;
    if (current != null) {
      await _licenseRepository.releaseDevice(current.deviceId); // best-effort
      downgraded = await _licenseRepository.downgradeToFree(current);
    }
    await Supabase.instance.client.auth.signOut();
    if (signedOutRole == 'staff' && shopId != null && shopId.isNotEmpty) {
      await _settings.setStaffRole(shopId, 'staff');
    }
    return AccountActionResult.success(null, license: downgraded);
  }

  /// Compatibility rejection for retired Online/Offline pricing.
  Future<AccountActionResult> setPricingTier(String tier) async =>
      const AccountActionResult.failure('retired_path');

  /// Create a Free account shop; trial is a separate explicit owner action.
  /// Existing local Free data is promoted through the recovery marker.
  Future<SignupResult> signupShop(
    String shopName,
    String email,
    String password,
  ) async {
    // Authenticated retries must use authoritative first-shop setup and normal
    // attachment, rather than synthesizing a Free cache over an existing plan.
    if (isSignedInWithRealAccount) {
      final result = await completeSocialSignup(shopName);
      if (result.ok) return SignupResult.success(result.license);
      return SignupResult.failure(
        result.needsWipeConfirmation
            ? 'shop_transition_required'
            : result.error,
      );
    }
    if (!Env.hasBackend) return const SignupResult.failure('no_backend');
    final deviceId = await _settings.deviceId();

    // Retry on `not_authenticated`: this call rides the device's anonymous
    // session (no shop_id claim exists yet — that's what signup_shop itself
    // mints), and a brand-new install can hit this Edge Function before that
    // anonymous sign-in has finished propagating server-side. That's a
    // startup timing race, not a real failure, so it's worth a couple of
    // refresh-and-retry passes before surfacing an error — this is the exact
    // failure the owner reported: the shop account WAS being created, but a
    // single unretried 401 here made a working signup look broken and (via
    // the shared error-code mapping) claim "signed in" when nothing had
    // signed in yet. Short, bounded backoff (not the general invokeActivate
    // path, which only proactively refreshes when there's no token at all).
    Map<String, dynamic>? data;
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
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
        break;
      } catch (e) {
        lastError = e;
        if (classifyInvokeError(e) != 'not_authenticated' || attempt == 2) {
          return SignupResult.failure(classifyInvokeError(e));
        }
        await refreshSessionBounded();
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    if (data == null) {
      final code = lastError == null
          ? 'server_error'
          : classifyInvokeError(lastError);
      // Remap: nothing has signed in yet at this point in signup, so the
      // shared 'not_authenticated' => "Signed in, but..." copy (accurate for
      // the post-sign-in attach path elsewhere) would be actively wrong
      // here. Fall through to the generic retry message instead.
      return SignupResult.failure(
        code == 'not_authenticated' ? 'signup_failed' : code,
      );
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
      plan: LicensePlan.free,
      expiresAt: DateTime.parse(expiresAtRaw),
      activatedAt:
          DateTime.tryParse(data['activated_at'] as String? ?? '') ?? now,
      lastVerifiedAt: now,
      deviceId: deviceId,
      tier: data['tier'] as String? ?? 'online',
      entitlement: data['entitlement'] as String?,
    );
    await _rememberLocalRole(lic.shopId);
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
        !current.shopId.startsWith('free-') ||
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
        return AccountActionResult.success(data['user_id'] as String?);
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
