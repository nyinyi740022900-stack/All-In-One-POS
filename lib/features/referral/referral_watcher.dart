import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/money.dart';
import '../../core/notifications.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import 'referral_providers.dart';

/// Watches the server-side referral commission total and fires a local
/// notification when it grows — the "🎉 commission earned" dopamine hit.
///
/// Commissions accrue server-side (when an admin approves a referred shop's
/// payment), so we poll: once at launch, on every app resume, and on a slow
/// timer. A watermark in settings means each new commission alerts exactly
/// once. This delivers the alert the next time the user opens the app; true
/// background delivery would need FCM (a later phase).
class ReferralWatcher {
  ReferralWatcher(this._ref) {
    _start();
  }

  final Ref _ref;
  Timer? _timer;
  _LifecycleHook? _hook;
  bool _checking = false;

  void _start() {
    if (!Env.hasBackend) return;
    _hook = _LifecycleHook(_check);
    WidgetsBinding.instance.addObserver(_hook!);
    // Defer the first check so it doesn't race app startup / auth.
    Timer(const Duration(seconds: 8), _check);
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => _check());
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      // No activated shop → no JWT shop context → nothing to read.
      if (_ref.read(licenseControllerProvider).license == null) return;

      final settings = _ref.read(settingsRepositoryProvider);
      final summary = await _ref.read(referralRepositoryProvider).summary();

      final seen = await settings.referralSeenEarned();
      if (seen == null) {
        // First run: baseline silently so we never alert for past earnings.
        await settings.setReferralSeenEarned(summary.earned);
        return;
      }
      if (summary.earned > seen) {
        final delta = summary.earned - seen;
        final code = await settings.savedLocale() ?? 'my';
        final l = await AppLocalizations.delegate.load(Locale(code));
        // No BuildContext here (this is a background watcher, not a widget),
        // so — like the locale above — the currency comes from `_ref`
        // directly rather than `Localizations.localeOf(context)`.
        final currency = _ref.read(shopCurrencyProvider);
        await NotificationService.instance.showCommission(
          title: l.referralNotifTitle,
          body: l.referralNotifBody(
              Money(delta).withCurrency(currency, code)),
        );
        await settings.setReferralSeenEarned(summary.earned);
        // Refresh any open referral screen.
        _ref.invalidate(referralSummaryProvider);
      }
    } catch (_) {
      // Offline / transient — try again on the next tick.
    } finally {
      _checking = false;
    }
  }

  void dispose() {
    _timer?.cancel();
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
final referralWatcherProvider = Provider<ReferralWatcher>((ref) {
  final watcher = ReferralWatcher(ref);
  ref.onDispose(watcher.dispose);
  return watcher;
});
