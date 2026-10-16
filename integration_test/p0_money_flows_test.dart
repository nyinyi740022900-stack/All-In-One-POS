import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/cash/cash_session_screen.dart';
import 'package:mm_pos/features/credit/credit_providers.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_status.dart';
import 'package:mm_pos/features/notifications/notification_center_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/sell/sell_screen.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// P0 money flows driven through the real screens on a simulator/device:
/// real taps, a real on-disk SQLite file opened through the same
/// `AppDatabase.forFile` path production uses, and the real repositories and
/// providers behind Sell, Checkout and the Cash register. Only the edges that
/// would reach the network (licence, notification feed) or need a signed-in
/// owner (role gates) are pinned.
///
/// No Supabase client is initialised, so the device is effectively offline:
/// every write must land locally and wait in the outbox.
///
///   `flutter test integration_test/p0_money_flows_test.dart -d <simulator>`
class _FreeLicence extends LicenseController {
  _FreeLicence(super.ref) {
    state = const LicenseState(
      loading: false,
      status: LicenseStatus(kind: LicenseStatusKind.active),
    );
  }

  @override
  Future<void> load() async {}
}

const _shopId = 'it-p0-shop';
final _l = lookupAppLocalizations(const Locale('en'));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late AppDatabase db;
  late File dbFile;
  late GlobalKey<NavigatorState> nav;

  setUp(() async {
    // A throwaway file beside — never inside — the app's real shop files.
    final tmp = await getTemporaryDirectory();
    dbFile = File(
      p.join(tmp.path, 'it_p0_${DateTime.now().microsecondsSinceEpoch}.sqlite'),
    );
    db = AppDatabase.forFile(dbFile);
    nav = GlobalKey<NavigatorState>();
  });

  tearDown(() async {
    await db.close();
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final f = File('${dbFile.path}$suffix');
      if (await f.exists()) await f.delete();
    }
  });

  Future<String> seedProduct({
    required String name,
    required int price,
    required int qty,
  }) => InventoryRepository(db, _shopId).upsertProduct(
    name: name,
    salePrice: price,
    costPrice: price ~/ 2,
    quantity: qty,
  );

  Future<ProviderContainer> pumpApp(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          deviceDatabaseProvider.overrideWithValue(db),
          shopIdProvider.overrideWith((ref) => _shopId),
          licenseControllerProvider.overrideWith((ref) => _FreeLicence(ref)),
          notificationUnreadCountProvider.overrideWith(
            (ref) => Stream.value(0),
          ),
          shopProfileProvider.overrideWith(
            (ref) async => const ShopProfile(name: 'IT shop'),
          ),
          isEffectiveOwnerProvider.overrideWith((ref) => true),
          canEditInventoryProvider.overrideWith((ref) => true),
          hasOwnerCapabilityProvider.overrideWith((ref, capability) => true),
        ],
        child: MaterialApp(
          navigatorKey: nav,
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(home.runtimeType).first),
    );
  }

  /// Sell tab → tap the product → Checkout → (optional setup) → Confirm sale
  /// → Done. Leaves the caller back on the Sell screen.
  Future<void> sellOne(
    WidgetTester tester,
    String productName, {
    Future<void> Function()? beforeConfirm,
  }) async {
    await tester.tap(find.text(productName).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${_l.sellCheckout}  (1)').first);
    await tester.pumpAndSettle();
    if (beforeConfirm != null) await beforeConfirm();
    final confirm = find.widgetWithText(FilledButton, _l.sellConfirm);
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text(_l.sellCompleted), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, _l.checkoutDone));
    await tester.pumpAndSettle();
  }

  Future<List<OutboxData>> outbox() => db.select(db.outbox).get();

  Future<int> stockOf(String productId) async {
    final rows = await InventoryRepository(db, _shopId).watchProducts().first;
    return rows.firstWhere((r) => r.product.id == productId).quantity;
  }

  testWidgets('cash sale: Sell → Checkout → ledger row, stock down, '
      'queued for sync', (tester) async {
    final coffee = await seedProduct(name: 'IT Coffee', price: 1500, qty: 10);
    await pumpApp(tester, const SellScreen());

    await sellOne(tester, 'IT Coffee');

    final sales = await db.select(db.sales).get();
    expect(sales, hasLength(1));
    expect(sales.single.total, 1500);
    expect(sales.single.paid, 1500);
    expect(sales.single.shopId, _shopId);
    expect(await stockOf(coffee), 9);

    final queued = await outbox();
    final tables = queued.map((o) => o.entityTable).toSet();
    expect(
      tables,
      containsAll(<String>['sales', 'sale_items', 'stock_movements']),
    );
    expect(
      queued.where((o) => o.entityTable == 'sales').single.rowId,
      sales.single.id,
    );
    // Cart is empty again — the next customer starts clean.
    expect(find.text('${_l.sellCheckout}  (1)'), findsNothing);
  });

  testWidgets('offline credit sale: customer owes the total, every row waits '
      'in the outbox untouched', (tester) async {
    await seedProduct(name: 'IT Rice', price: 42000, qty: 3);
    final c = await pumpApp(tester, const SellScreen());

    await sellOne(
      tester,
      'IT Rice',
      beforeConfirm: () async {
        await tester.tap(find.text(_l.paymentCredit).first);
        await tester.pumpAndSettle();
        // Confirm without a name first: the sale must be refused, not saved.
        final confirm = find.widgetWithText(FilledButton, _l.sellConfirm);
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(await db.select(db.sales).get(), isEmpty);
        final name = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.labelText ?? '').startsWith(_l.creditCustomerName),
        );
        // The refusal is visible, not silent: the name field carries the
        // error (proves the nameless Confirm tap actually landed).
        expect(
          tester.widget<TextField>(name.first).decoration?.errorText,
          isNotNull,
        );
        await tester.enterText(name.first, 'Daw IT Test');
        await tester.pumpAndSettle();
      },
    );

    final sale = (await db.select(db.sales).get()).single;
    expect(sale.total, 42000);
    expect(sale.paid, 0);

    final owed = c.read(creditCustomersProvider);
    expect(owed.map((o) => o.name), contains('Daw IT Test'));
    expect(owed.firstWhere((o) => o.name == 'Daw IT Test').outstanding, 42000);

    final queued = await outbox();
    expect(queued.map((o) => o.entityTable), contains('sales'));
    // Nothing tried to push: offline work is kept, not dropped or failed.
    expect(queued.every((o) => o.attempts == 0), isTrue);
  });

  testWidgets('cash register: open with a float, a cash sale moves expected '
      'cash, close records the shortfall', (tester) async {
    await seedProduct(name: 'IT Tea', price: 1500, qty: 5);
    await pumpApp(tester, const CashSessionScreen());

    Future<void> amountDialog(String confirmLabel, String digits) async {
      final dialog = find.byType(Dialog);
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        digits,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(FilledButton, confirmLabel),
        ),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text(_l.cashOpenRegister).first);
    await tester.pumpAndSettle();
    await amountDialog(_l.cashOpenRegister, '10000');
    expect(find.text(_l.cashRegisterOpen), findsWidgets);

    // Ring up a cash sale on the Sell screen, then come back to the drawer.
    nav.currentState!.push(
      MaterialPageRoute(builder: (_) => const SellScreen()),
    );
    await tester.pumpAndSettle();
    await sellOne(tester, 'IT Tea');
    nav.currentState!.pop();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    final session = (await db.select(db.cashSessions).get()).single;
    expect(session.openingAmount, 10000);

    await tester.tap(find.text(_l.cashCloseRegister).first);
    await tester.pumpAndSettle();
    // Expected inside the close dialog = float 10,000 + sale 1,500.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.textContaining('11,500'),
      ),
      findsWidgets,
    );
    await amountDialog(_l.cashCloseRegister, '11000');

    final closed = (await db.select(db.cashSessions).get()).single;
    expect(closed.closingAmount, 11000);
    expect(closed.closedAt, isNotNull);
    expect(closed.expectedCashAtClose, 11500);
    expect(find.text(_l.cashNoSession), findsOneWidget);
  });
}
