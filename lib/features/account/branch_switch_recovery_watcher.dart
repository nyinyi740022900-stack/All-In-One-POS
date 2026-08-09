import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../data/sync/sync_providers.dart';
import 'branch_providers.dart';

/// Auto-resolves an interrupted branch switch without the owner needing to
/// reopen Settings > Branches. Modeled on [ReferralWatcher] (same
/// plain-class + WidgetsBindingObserver + Provider pattern).
///
/// A recovery record on disk means `switchBranch()` reached at least
/// `clearingOldData` (see `BranchRepository.switchBranch`) — the account
/// claim switch already succeeded server-side by that point, so this is
/// deliberately NOT gated on `needsSyncRetry`: that flag is only set by the
/// UI *after* a failed retry, but a record can also be left behind by an app
/// kill right after a *successful* `switchBranch()` return, before the UI
/// ever got to call `markSwitchNeedsSyncRetry`. `verifyPostSwitch` is
/// side-effect-free, so checking unconditionally is safe — a false-positive
/// record (e.g. the app died before the switch RPC even ran) just re-marks
/// needing retry, same as today's manual path.
class BranchSwitchRecoveryWatcher {
  BranchSwitchRecoveryWatcher(this._ref) {
    _start();
  }

  final Ref _ref;
  Timer? _deferredCheck;
  StreamSubscription? _connSub;
  _LifecycleHook? _hook;
  bool _checking = false;

  void _start() {
    if (!Env.hasBackend) return;
    _hook = _LifecycleHook(_check);
    WidgetsBinding.instance.addObserver(_hook!);
    // Deferred so it doesn't race auth/session bootstrap on cold start.
    _deferredCheck = Timer(const Duration(seconds: 3), _check);
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) _check();
    });
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final recovery = await _ref
          .read(branchRepositoryProvider)
          .switchRecoveryState();
      if (recovery == null) return;
      var online = true;
      try {
        final results = await Connectivity().checkConnectivity();
        online = results.any((r) => r != ConnectivityResult.none);
      } catch (_) {}
      if (!online) return;

      await _ref.read(syncControllerProvider.notifier).syncUntilDrained();
      final verify = await _ref
          .read(branchRepositoryProvider)
          .verifyPostSwitch(recovery.toShopId);
      if (verify.ok) {
        await _ref.read(branchRepositoryProvider).clearSwitchRecoveryState();
      } else {
        await _ref
            .read(branchRepositoryProvider)
            .markSwitchNeedsSyncRetry(
              toShopId: recovery.toShopId,
              fromShopId: recovery.fromShopId,
              token: recovery.token,
              lastError: 'post_switch_verify_failed',
            );
      }
    } catch (_) {
      // Offline / transient — the next connectivity change or resume retries.
    } finally {
      _checking = false;
    }
  }

  void dispose() {
    _deferredCheck?.cancel();
    _connSub?.cancel();
    if (_hook != null) WidgetsBinding.instance.removeObserver(_hook!);
  }
}

class _LifecycleHook with WidgetsBindingObserver {
  _LifecycleHook(this.onResume);
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// Kept alive for the app's lifetime (watched in [MmPosApp]).
final branchSwitchRecoveryWatcherProvider =
    Provider<BranchSwitchRecoveryWatcher>((ref) {
      final watcher = BranchSwitchRecoveryWatcher(ref);
      ref.onDispose(watcher.dispose);
      return watcher;
    });
