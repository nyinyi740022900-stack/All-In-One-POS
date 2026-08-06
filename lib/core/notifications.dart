import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper over `flutter_local_notifications` for referral-earnings and
/// new storefront-order alerts. Initializes lazily on first use and requests
/// the runtime permission then, so a user who never needs alerts is never
/// prompted.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // Stable ids so repeated alerts replace rather than stack up.
  static const int _referralId = 8801;
  static const int _storefrontOrderId = 8802;

  Future<void> _ensureInit() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    // Android 13+ needs an explicit runtime grant.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  /// Fire (or refresh) the referral commission alert.
  Future<void> showCommission({
    required String title,
    required String body,
  }) async {
    try {
      await _ensureInit();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'referral_earnings',
          'Referral earnings',
          channelDescription: 'Alerts when you earn a referral commission',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      await _plugin.show(_referralId, title, body, details,
          payload: 'referral');
    } catch (e) {
      // Never let a notification failure affect app flow.
      debugPrint('Referral notification failed: $e');
    }
  }

  /// Fire (or refresh) the new-storefront-order alert.
  Future<void> showStorefrontOrder({
    required String title,
    required String body,
  }) async {
    try {
      await _ensureInit();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'storefront_orders',
          'Web storefront orders',
          channelDescription: 'Alerts when a customer places an online order',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      await _plugin.show(_storefrontOrderId, title, body, details,
          payload: 'storefront_order');
    } catch (e) {
      debugPrint('Storefront order notification failed: $e');
    }
  }
}
