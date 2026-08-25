import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/notifications.dart';
import '../../l10n/app_localizations.dart';
import '../printing/printing_providers.dart';
import 'license_providers.dart';
import 'license_status.dart';

/// A due expiry reminder: how many whole days are left, and the watermark to
/// record once it has been shown.
class ExpiryReminder {
  const ExpiryReminder({required this.daysLeft, required this.stamp});

  final int daysLeft;

  /// `<expiresAt ISO>|<threshold>` — see [computeExpiryReminder].
  final String stamp;
}

/// Warn at a week out, then again with three days and one day left, and a
/// last time on the final day. Descending, so the threshold picked is always
/// the tightest one the shop has crossed — re-warning at 7 after they have
/// already seen 3 would read as going backwards.
const kExpiryReminderThresholds = [7, 3, 1, 0];

/// Decides whether a licence-expiry reminder is due — the whole rule, with
/// no I/O, so every branch below is unit-tested rather than reasoned about.
///
/// Returns null when nothing should fire. [lastWarned] is the previously
/// stored [ExpiryReminder.stamp] for this shop; because the stamp embeds the
/// expiry date, renewing invalidates it on its own and the next cycle warns
/// again with no explicit reset anywhere.
ExpiryReminder? computeExpiryReminder({
  required DateTime? expiresAt,
  required DateTime now,
  required LicensePlan? plan,
  required String? lastWarned,
}) {
  // Free never expires. It is not a lapsed subscription, it is the plan —
  // warning a Free shop about an expiry it does not have would be a lie.
  if (expiresAt == null || plan == LicensePlan.free) return null;

  final daysLeft = wholeDaysUntil(expiresAt, now);
  // Already lapsed: the Sell-screen banner and the License screen both say
  // so plainly. A notification at that point is scolding, not helping.
  if (daysLeft < 0) return null;

  final threshold = kExpiryReminderThresholds.firstWhere(
    (t) => daysLeft <= t,
    orElse: () => -1,
  );
  if (threshold < 0) return null;

  final stamp = '${expiresAt.toIso8601String()}|$threshold';
  if (lastWarned == stamp) return null;
  return ExpiryReminder(daysLeft: daysLeft, stamp: stamp);
}

/// Reminds the owner before Premium lapses.
///
/// This is the half of renewal we *can* automate. MyanMyanPay's MMQR is a
/// customer-push payment — there is no mandate or card on file, so nothing
/// can charge a shop automatically; every renewal is a deliberate act. What
/// removes the surprise is telling them in time, which is exactly what this
/// does.
///
/// Local notifications only, delivered the next time the app is open, same
/// as [ReferralWatcher] — true background delivery would need FCM. That is
/// enough here: a POS is opened every trading day, and the thresholds below
/// give a week of chances.
class LicenseExpiryWatcher {
  LicenseExpiryWatcher(this._ref) {
    _start();
  }

  final Ref _ref;
  Timer? _timer;
  _LifecycleHook? _hook;
  bool _checking = false;

  void _start() {
    // Same gate as ReferralWatcher/StorefrontOrderWatcher: a build with no
    // backend compiled in has no licensing service behind it, so there is
    // no expiry to remind anyone about — and registering app-lifetime timers
    // in that case would also leave every widget test with a pending timer.
    if (!Env.hasBackend) return;
    _hook = _LifecycleHook(_check);
    WidgetsBinding.instance.addObserver(_hook!);
    // Defer past app startup, then check on a slow timer. Expiry moves once
    // a day, so anything faster is pure noise.
    Timer(const Duration(seconds: 12), _check);
    _timer = Timer.periodic(const Duration(hours: 6), (_) => _check());
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final state = _ref.read(licenseControllerProvider);
      final license = state.license;
      final expiresAt = state.status.expiresAt;

      if (license == null || expiresAt == null) return;

      final shopId = license.shopId;
      final settings = _ref.read(settingsRepositoryProvider);
      final due = computeExpiryReminder(
        expiresAt: expiresAt,
        now: DateTime.now(),
        plan: license.plan,
        lastWarned: await settings.licenseExpiryWarned(shopId),
      );
      if (due == null) return;
      final daysLeft = due.daysLeft;

      final code = await settings.savedLocale() ?? 'my';
      final l = await AppLocalizations.delegate.load(Locale(code));
      final shopName = await _shopName(l);

      await NotificationService.instance.showLicenseExpiring(
        title: daysLeft == 0
            ? l.licenseExpiryNotifTitleToday
            : l.licenseExpiryNotifTitle,
        body: daysLeft == 0
            ? l.licenseExpiryNotifBodyToday(shopName)
            : l.licenseExpiryNotifBody(daysLeft, shopName),
      );
      await settings.setLicenseExpiryWarned(shopId, due.stamp);
    } catch (_) {
      // Offline / transient — the next tick tries again.
    } finally {
      _checking = false;
    }
  }

  Future<String> _shopName(AppLocalizations l) async {
    try {
      final name = (await _ref.read(shopProfileProvider.future)).name;
      if (name.trim().isNotEmpty) return name.trim();
    } catch (_) {
      // Profile not loaded yet — fall through to the generic wording.
    }
    return l.appTitle;
  }

  void dispose() {
    _timer?.cancel();
    if (_hook != null) WidgetsBinding.instance.removeObserver(_hook!);
  }
}

/// Whole days from [now] to [expiresAt], counted on calendar dates rather
/// than elapsed hours — a licence expiring at 23:00 tonight is "0 days
/// left", not "1", which is what the owner sees on the Sell banner too.
int wholeDaysUntil(DateTime expiresAt, DateTime now) {
  final end = DateTime(expiresAt.year, expiresAt.month, expiresAt.day);
  final today = DateTime(now.year, now.month, now.day);
  return end.difference(today).inDays;
}

class _LifecycleHook with WidgetsBindingObserver {
  _LifecycleHook(this.onResume);
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// Kept alive for the app's lifetime (watched in `MmPosApp`), same as
/// [referralWatcherProvider].
final licenseExpiryWatcherProvider = Provider<LicenseExpiryWatcher>((ref) {
  final watcher = LicenseExpiryWatcher(ref);
  ref.onDispose(watcher.dispose);
  return watcher;
});
