import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import 'notification_center_repository.dart';

final notificationCenterRepositoryProvider =
    Provider<NotificationCenterRepository>((ref) {
      return NotificationCenterRepository(ref.watch(databaseProvider));
    });

/// The list behind the bell. Watches the table directly, so a row written by
/// either watcher shows up without anything having to invalidate it.
final notificationCenterProvider = StreamProvider<List<AppNotification>>((ref) {
  final shopId = ref.watch(shopIdProvider);
  return ref.watch(notificationCenterRepositoryProvider).watch(shopId);
});

/// Drives the badge on the bell.
final notificationUnreadCountProvider = StreamProvider<int>((ref) {
  final shopId = ref.watch(shopIdProvider);
  return ref
      .watch(notificationCenterRepositoryProvider)
      .watchUnreadCount(shopId);
});
