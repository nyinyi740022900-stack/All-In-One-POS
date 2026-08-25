import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper over `flutter_local_notifications` for referral-earnings,
/// new storefront-order and licence-expiry alerts. Initializes lazily on
/// first use and requests the runtime permission then, so a user who never
/// needs alerts is never prompted.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // Stable ids so repeated alerts replace rather than stack up.
  static const int _referralId = 8801;
  static const int _storefrontOrderId = 8802;
  static const int _licenseExpiryId = 8803;

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

  /// Fire (or refresh) the licence-expiry reminder.
  ///
  /// One stable id, so the T-7 alert is replaced by T-3 rather than leaving
  /// three contradictory notices in the tray. Deliberately says nothing
  /// about price or where to pay — on a store build there is no purchase UI
  /// to send anyone to (see `lib/core/build_flags.dart`), and a
  /// notification is as much a call to action as a button is.
  Future<void> showLicenseExpiring({
    required String title,
    required String body,
  }) async {
    try {
      await _ensureInit();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'license_expiry',
          'Licence expiry',
          channelDescription: 'Reminds you before Premium expires',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      await _plugin.show(_licenseExpiryId, title, body, details,
          payload: 'license_expiry');
    } catch (e) {
      debugPrint('License expiry notification failed: $e');
    }
  }
}
