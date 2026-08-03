import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/providers.dart';
import '../printing/printing_providers.dart';
import 'license_model.dart';
import 'license_repository.dart';
import 'license_status.dart';

final licenseRepositoryProvider = Provider<LicenseRepository>((ref) {
  return LicenseRepository(ref.watch(settingsRepositoryProvider));
});

/// The shop's device slots. Re-fetch with `ref.invalidate` after adding or
/// releasing a device (no realtime/stream backing this — it's a plain
/// on-demand read of the `licenses` table).
final shopDevicesProvider = FutureProvider.autoDispose<List<ShopDevice>>((ref) {
  return ref.watch(licenseRepositoryProvider).listDevices();
});

class LicenseState {
  final bool loading;
  final CachedLicense? license;
  final LicenseStatus status;

  const LicenseState({
    this.loading = true,
    this.license,
    this.status = LicenseStatus.none,
  });

  bool get canSell => status.canSell;
}

final licenseControllerProvider =
    StateNotifierProvider<LicenseController, LicenseState>((ref) {
  return LicenseController(ref)..load();
});

class LicenseController extends StateNotifier<LicenseState> {
  LicenseController(this._ref) : super(const LicenseState());

  final Ref _ref;
  Timer? _reverifyTimer;

  LicenseRepository get _repo => _ref.read(licenseRepositoryProvider);

  Future<void> load() async {
    final lic = await _repo.current();
    _apply(lic);
    // Pick up admin extensions/revocations without user action: re-verify once
    // at launch and then periodically (best-effort; offline is a no-op).
    if (Env.hasBackend) {
      _silentReverify();
      _reverifyTimer ??= Timer.periodic(
          const Duration(hours: 6), (_) => _silentReverify());
    }
  }

  Future<void> _silentReverify() async {
    if (state.license == null) return;
    try {
      await refreshOnline();
    } catch (_) {/* offline / transient — keep cached */}
  }

  @override
  void dispose() {
    _reverifyTimer?.cancel();
    super.dispose();
  }

  Future<ActivationResult> activate(String key) async {
    final result = await _repo.activate(key);
    if (result.ok) _apply(result.license);
    return result;
  }

  Future<void> deactivate() async {
    await _repo.deactivate();
    _apply(null);
  }

  /// Starts the one-time free 2-month trial. Returns false if already used.
  Future<bool> startFreeTrial() async {
    final lic = await _repo.startFreeTrial();
    if (lic == null) return false;
    _apply(lic);
    return true;
  }

  /// Re-checks the license online (same key + device) to pick up an extension
  /// an admin approved after a renewal payment. Reuses `activate`, which
  /// returns the current server-side expiry. No-op offline / with no license.
  Future<ActivationResult> refreshOnline() async {
    final lic = state.license;
    if (lic == null) {
      return const ActivationResult.failure('not_activated');
    }
    // A local trial or an offline signed token has nothing to re-verify online
    // — treat it as up to date instead of a misleading "activation failed".
    if (lic.key == 'FREE-TRIAL' || lic.key.startsWith('MMPOS1.')) {
      return ActivationResult.success(lic);
    }
    final result = await _repo.activate(lic.key);
    if (result.ok) _apply(result.license);
    return result;
  }

  /// Applies a [CachedLicense] that was already persisted elsewhere (e.g. by
  /// [LicenseRepository.saveExternal] after a branch switch) — same
  /// shopId-binding + status recompute `activate()`/`load()` already do.
  void applyExternal(CachedLicense lic) => _apply(lic);

  void _apply(CachedLicense? lic) {
    final status = computeLicenseStatus(
      expiresAt: lic?.expiresAt,
      now: DateTime.now(),
      plan: lic?.plan,
      activated: lic != null,
    );
    // Bind the active shop so all data scopes to it.
    if (lic != null) {
      _ref.read(shopIdProvider.notifier).state = lic.shopId;
    }
    state = LicenseState(loading: false, license: lic, status: status);
  }
}
