import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/notifications/notification_center_repository.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// The notification centre is device-local but **shop-scoped**: one phone can
/// switch between branches (`BranchRepository.switchBranch`), and a branch
/// must never see the other's alerts or clear them by accident. That is the
/// multi-tenant case CLAUDE.md's ripple check asks for by name, and it is not
/// something the analyzer or a single-shop test would ever catch.
void main() {
  late AppDatabase db;
  late NotificationCenterRepository repo;

  const shopA = 'shop-a';
  const shopB = 'shop-b';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = NotificationCenterRepository(db);
  });

  tearDown(() async => db.close());

  Future<void> addOrder(String shopId, {int count = 1, DateTime? at}) =>
      repo.add(
        shopId: shopId,
        kind: NotificationKinds.storefrontOrder,
        payload: {'count': count},
        createdAt: at,
      );

  group('shop scoping', () {
    test('a shop sees only its own notifications', () async {
      await addOrder(shopA);
      await addOrder(shopA);
      await addOrder(shopB);

      expect((await repo.watch(shopA).first).length, 2);
      expect((await repo.watch(shopB).first).length, 1);
    });

    test('the unread badge counts only this shop', () async {
      await addOrder(shopA);
      await addOrder(shopB);
      await addOrder(shopB);

      expect(await repo.watchUnreadCount(shopA).first, 1);
      expect(await repo.watchUnreadCount(shopB).first, 2);
    });

    test('marking read does not touch the other shop', () async {
      await addOrder(shopA);
      await addOrder(shopB);

      await repo.markAllRead(shopA);

      expect(await repo.watchUnreadCount(shopA).first, 0);
      expect(
        await repo.watchUnreadCount(shopB).first,
        1,
        reason: 'clearing one branch\'s badge must not silently clear the '
            'other branch the device can switch back to.',
      );
    });

    test('clearing does not delete the other shop\'s rows', () async {
      await addOrder(shopA);
      await addOrder(shopB);

      await repo.clear(shopA);

      expect((await repo.watch(shopA).first), isEmpty);
      expect((await repo.watch(shopB).first).length, 1);
    });

    test('an empty shop id is a no-op, not a write with a blank key', () async {
      await addOrder('');
      expect(await repo.watchUnreadCount('').first, 0);
      final all = await db.select(db.appNotifications).get();
      expect(all, isEmpty);
    });
  });

  group('retention', () {
    test('keeps the newest and drops the rest', () async {
      final base = DateTime(2026, 1, 1);
      // One more than the cap, each a minute apart so the ordering is real
      // rather than dependent on insert speed.
      for (var i = 0; i < NotificationCenterRepository.keepPerShop + 5; i++) {
        await addOrder(shopA, count: i, at: base.add(Duration(minutes: i)));
      }

      final rows = await db.select(db.appNotifications).get();
      expect(rows.length, lessThanOrEqualTo(
        NotificationCenterRepository.keepPerShop,
      ));

      final newest = (await repo.watch(shopA).first).first;
      expect(
        newest.createdAt,
        base.add(Duration(
          minutes: NotificationCenterRepository.keepPerShop + 4,
        )),
        reason: 'pruning must drop the oldest, never the newest.',
      );
    });
  });

  group('rendering', () {
    setUpAll(() => WidgetsFlutterBinding.ensureInitialized());

    test('follows the app\'s current language, not the one it fired in',
        () async {
      // The whole reason rows store kind + payload instead of the rendered
      // strings: the tray copy is fixed at fire time, this list is not.
      await addOrder(shopA, count: 3);
      final row = (await repo.watch(shopA).first).single;

      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final my = await AppLocalizations.delegate.load(const Locale('my'));

      final inEnglish = notificationText(en, row)!;
      final inMyanmar = notificationText(my, row)!;

      expect(inEnglish.body, contains('3'));
      expect(inMyanmar.body, contains('3'));
      expect(
        inEnglish.title,
        isNot(inMyanmar.title),
        reason: 'the same row must read differently in the two languages.',
      );
    });

    test('a kind this build does not know is skipped, not crashed on',
        () async {
      await repo.add(
        shopId: shopA,
        kind: 'something_a_newer_build_writes',
        payload: {'whatever': 1},
      );
      final row = (await repo.watch(shopA).first).single;
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(notificationText(en, row), isNull);
    });

    test('a malformed payload still renders its headline', () async {
      await db.into(db.appNotifications).insert(
            AppNotificationsCompanion.insert(
              id: 'broken',
              shopId: shopA,
              kind: NotificationKinds.storefrontOrder,
              payload: const Value('not json at all'),
              createdAt: DateTime(2026, 1, 1),
            ),
          );
      final row = (await repo.watch(shopA).first).single;
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(notificationText(en, row)?.title, isNotNull);
    });
  });
}
