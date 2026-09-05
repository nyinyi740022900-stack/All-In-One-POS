import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications.dart';
import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../notifications/notification_center_providers.dart';
import '../notifications/notification_center_repository.dart';
import '../orders/orders_providers.dart';
import '../printing/printing_providers.dart';

/// Watches local `orders` (channel == storefront) and fires a local
/// notification when new rows appear after sync — same "next time you open
/// the app" delivery model as [LicenseExpiryWatcher] (FCM is a later phase).
class StorefrontOrderWatcher {
  StorefrontOrderWatcher(this._ref) {
    _ref.listen<AsyncValue<List<Order>>>(ordersStreamProvider, (_, next) {
      next.whenData(_onOrders);
    });
  }

  final Ref _ref;
  bool _checking = false;

  Future<void> _onOrders(List<Order> all) async {
    if (_checking) return;
    if (_ref.read(licenseControllerProvider).license == null) return;
    final shopId = _ref.read(shopIdProvider);
    if (shopId.isEmpty) return;

    _checking = true;
    try {
      final storefront = all.where((o) => o.channel == 'storefront').toList();
      final settings = _ref.read(settingsRepositoryProvider);
      final seen = await settings.storefrontSeenOrderCreatedMs(shopId);

      int maxMs = 0;
      for (final o in storefront) {
        final ms = o.createdAt.millisecondsSinceEpoch;
        if (ms > maxMs) maxMs = ms;
      }

      if (seen == null) {
        await settings.setStorefrontSeenOrderCreatedMs(shopId, maxMs);
        return;
      }

      final newer =
          storefront.where((o) => o.createdAt.millisecondsSinceEpoch > seen);
      final count = newer.length;
      if (count == 0) return;

      final code = await settings.savedLocale() ?? 'my';
      final l = await AppLocalizations.delegate.load(Locale(code));
      await NotificationService.instance.showStorefrontOrder(
        title: l.storefrontOrderNotifTitle,
        body: l.storefrontOrderNotifBody(count),
      );
      // Also record it for the in-app bell. Stored as kind + count, not as
      // the rendered strings above: the tray copy is fixed in the locale of
      // this moment, but the list is re-read later and follows whatever
      // language the app is in then.
      await _ref.read(notificationCenterRepositoryProvider).add(
        shopId: shopId,
        kind: NotificationKinds.storefrontOrder,
        payload: {'count': count},
      );
      await settings.setStorefrontSeenOrderCreatedMs(shopId, maxMs);
    } catch (_) {
      // Offline / DB rebound — next stream emission retries.
    } finally {
      _checking = false;
    }
  }
}

/// Kept alive for the app's lifetime (watched in [MmPosApp]).
final storefrontOrderWatcherProvider = Provider<StorefrontOrderWatcher>((ref) {
  return StorefrontOrderWatcher(ref);
});
