import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';

/// What a stored notification says, rendered in the caller's *current*
/// locale rather than the one it was fired in.
class NotificationText {
  const NotificationText({required this.title, required this.body});
  final String title;
  final String body;
}

/// Renders a row for display. Returns null for a `kind` this build does not
/// know, so a row written by a newer build is skipped instead of crashing an
/// older one.
NotificationText? notificationText(AppLocalizations l, AppNotification n) {
  final Map<String, dynamic> p;
  try {
    final decoded = jsonDecode(n.payload);
    p = decoded is Map<String, dynamic> ? decoded : const {};
  } catch (_) {
    // A malformed payload is not worth losing the row over — the kind alone
    // still carries the headline.
    return _fromKind(l, n.kind, const {});
  }
  return _fromKind(l, n.kind, p);
}

NotificationText? _fromKind(
  AppLocalizations l,
  String kind,
  Map<String, dynamic> p,
) {
  switch (kind) {
    case NotificationKinds.storefrontOrder:
      final count = (p['count'] as num?)?.toInt() ?? 1;
      return NotificationText(
        title: l.storefrontOrderNotifTitle,
        body: l.storefrontOrderNotifBody(count),
      );
    case NotificationKinds.licenseExpiry:
      final days = (p['daysLeft'] as num?)?.toInt() ?? 0;
      final shop = (p['shopName'] as String?) ?? l.appTitle;
      return NotificationText(
        title: days == 0
            ? l.licenseExpiryNotifTitleToday
            : l.licenseExpiryNotifTitle,
        body: days == 0
            ? l.licenseExpiryNotifBodyToday(shop)
            : l.licenseExpiryNotifBody(days, shop),
      );
    default:
      return null;
  }
}

abstract final class NotificationKinds {
  static const storefrontOrder = 'storefront_order';
  static const licenseExpiry = 'license_expiry';
}

/// The in-app notification centre's store. Device-local (see
/// [AppNotifications]) and scoped by shop, so a branch switch shows that
/// branch's history rather than the previous one's.
class NotificationCenterRepository {
  NotificationCenterRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// How many rows a shop keeps. Old alerts have no value once read — this
  /// is a log of the last few days, not an archive — and an unbounded table
  /// on a phone that never reinstalls only ever grows.
  static const int keepPerShop = 60;

  Stream<List<AppNotification>> watch(String shopId) {
    if (shopId.isEmpty) return Stream.value(const []);
    return (_db.select(_db.appNotifications)
          ..where((t) => t.shopId.equals(shopId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(keepPerShop))
        .watch();
  }

  Stream<int> watchUnreadCount(String shopId) {
    if (shopId.isEmpty) return Stream.value(0);
    final count = _db.appNotifications.id.count();
    final q = _db.selectOnly(_db.appNotifications)
      ..addColumns([count])
      ..where(
        _db.appNotifications.shopId.equals(shopId) &
            _db.appNotifications.readAt.isNull(),
      );
    return q.map((r) => r.read(count) ?? 0).watchSingle();
  }

  Future<void> add({
    required String shopId,
    required String kind,
    Map<String, Object?> payload = const {},
    DateTime? createdAt,
  }) async {
    if (shopId.isEmpty) return;
    await _db
        .into(_db.appNotifications)
        .insert(
          AppNotificationsCompanion.insert(
            id: _uuid.v4(),
            shopId: shopId,
            kind: kind,
            payload: Value(jsonEncode(payload)),
            createdAt: createdAt ?? DateTime.now(),
          ),
        );
    await _prune(shopId);
  }

  Future<void> markAllRead(String shopId) async {
    if (shopId.isEmpty) return;
    await (_db.update(_db.appNotifications)
          ..where((t) => t.shopId.equals(shopId) & t.readAt.isNull()))
        .write(AppNotificationsCompanion(readAt: Value(DateTime.now())));
  }

  Future<void> clear(String shopId) async {
    if (shopId.isEmpty) return;
    await (_db.delete(
      _db.appNotifications,
    )..where((t) => t.shopId.equals(shopId))).go();
  }

  /// Drops everything past [keepPerShop] for this shop, oldest first.
  Future<void> _prune(String shopId) async {
    final keep =
        await (_db.select(_db.appNotifications)
              ..where((t) => t.shopId.equals(shopId))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(keepPerShop))
            .get();
    if (keep.length < keepPerShop) return;
    final oldest = keep.last.createdAt;
    await (_db.delete(_db.appNotifications)..where(
          (t) =>
              t.shopId.equals(shopId) & t.createdAt.isSmallerThanValue(oldest),
        ))
        .go();
  }
}
