import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/domain/product_with_stock.dart';
import 'package:mm_pos/features/accounts/payment_account_providers.dart';
import 'package:mm_pos/features/customers/customer_providers.dart';
import 'package:mm_pos/features/inventory/inventory_providers.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_status.dart';
import 'package:mm_pos/features/notifications/notification_center_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/sell/cart.dart';
import 'package:mm_pos/features/staff/staff_ui.dart';
import 'package:mm_pos/features/sell/held_sales_provider.dart';
import 'package:mm_pos/features/sell/sales_providers.dart';
import 'package:mm_pos/features/sell/sell_screen.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

class _License extends LicenseController {
  _License(super.ref) {
    state = const LicenseState(
      loading: false,
      status: LicenseStatus(kind: LicenseStatusKind.active),
    );
  }
  @override
  Future<void> load() async {}
}

ProductWithStock _row(int i) => ProductWithStock(
  product: Product(
    id: 'p$i',
    shopId: '',
    name: 'Product $i',
    categoryId: 'cat',
    costPrice: 200,
    salePrice: 1234567,
    unit: 'pcs',
    isActive: true,
    sellOnline: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    isDeleted: false,
    dirty: false,
  ),
  quantity: 50,
  reorderLevel: 5,
);

const _longName = 'Daw အလွန်ရှည်လျားသောဝန်ထမ်းအမည် စာရေးမ မေသန္တာလှိုင်';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, file) in [
      ('Inter', 'Inter-Regular.ttf'),
      ('NotoSansMyanmar', 'NotoSansMyanmar-Regular.ttf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$file'));
      await loader.load();
    }
  });
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Size size = const Size(360, 800),
    double scale = 1,
    List<ProductWithStock>? rows,
    bool dark = false,
    bool owner = false,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          deviceDatabaseProvider.overrideWithValue(db),
          shopIdProvider.overrideWith(
            (ref) => '',
          ), // no debug seeding in the harness
          productsStreamProvider.overrideWith(
            (ref) => Stream.value(rows ?? [_row(1), _row(2)]),
          ),
          categoriesStreamProvider.overrideWith(
            (ref) => Stream.value(const <Category>[]),
          ),
          trackStockProvider.overrideWith((ref) => Stream.value(true)),
          shopProfileProvider.overrideWith(
            (ref) async => const ShopProfile(name: 'Test shop'),
          ),
          canEditInventoryProvider.overrideWith((ref) => true),
          isEffectiveOwnerProvider.overrideWith((ref) => owner),
          activeStaffNameProvider.overrideWith((ref) => _longName),
          hasOwnerCapabilityProvider.overrideWith((ref, capability) => false),
          licenseControllerProvider.overrideWith((ref) => _License(ref)),
          notificationUnreadCountProvider.overrideWith(
            (ref) => Stream.value(0),
          ),
          salesStreamProvider.overrideWith(
            (ref) => Stream.value(const <Sale>[]),
          ),
          customersStreamProvider.overrideWith(
            (ref) => Stream.value(const <Customer>[]),
          ),
          paymentAccountsProvider.overrideWith(
            (ref) => Stream.value(const <PaymentAccount>[]),
          ),
        ],
        child: MaterialApp(
          theme: dark
              ? AppTheme.dark(localeCode: locale.languageCode)
              : AppTheme.light(localeCode: locale.languageCode),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const SellScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(SellScreen)));
  }

  Finder menuItem(String value) => find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem<String> && widget.value == value,
  );

  Future<void> openMenu(WidgetTester tester) async {
    final l = AppLocalizations.of(tester.element(find.byType(SellScreen)));
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byTooltip(l.commonMore),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final locale in [const Locale('en'), const Locale('my')]) {
    for (final dark in [false, true]) {
      for (final width in [320.0, 430.0, 1024.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            'Sell toolbar ${locale.languageCode} ${dark ? "dark" : "light"} width $width scale $scale keeps title and actions usable',
            (tester) async {
              await pump(
                tester,
                size: Size(width, 1000),
                locale: locale,
                dark: dark,
                scale: scale,
              );
              final l = AppLocalizations.of(
                tester.element(find.byType(SellScreen)),
              );
              final bar = find.byType(AppBar);
              final title = find.descendant(
                of: bar,
                matching: find.text(l.sellTitle),
              );
              final scanner = find.descendant(
                of: bar,
                matching: find.byTooltip(l.scanBarcode),
              );
              final more = find.descendant(
                of: bar,
                matching: find.byTooltip(l.commonMore),
              );
              expect(title, findsOneWidget);
              expect(scanner, findsOneWidget);
              expect(more, findsOneWidget);
              expect(
                find.descendant(
                  of: bar,
                  matching: find.byIcon(Icons.notifications_none),
                ),
                findsOneWidget,
              );
              for (final icon in [
                Icons.pause_circle_outline,
                Icons.bookmark_border,
                Icons.remove_shopping_cart,
              ]) {
                expect(
                  find.descendant(of: bar, matching: find.byIcon(icon)),
                  findsNothing,
                );
              }
              final titleRect = tester.getRect(title);
              expect(titleRect.left, greaterThanOrEqualTo(0));
              expect(titleRect.width, greaterThan(0));
              expect(
                titleRect.right,
                lessThanOrEqualTo(tester.getRect(scanner).left),
              );
              final titleParagraph = tester.renderObject<RenderParagraph>(
                title,
              );
              expect(titleParagraph.didExceedMaxLines, isFalse);
              final staff = find.descendant(
                of: bar,
                matching: find.byType(StaffBadge),
              );
              expect(staff, findsOneWidget);
              expect(
                find.descendant(of: staff, matching: find.byTooltip(_longName)),
                findsOneWidget,
              );
              final name = tester.widget<Text>(
                find.descendant(of: staff, matching: find.text(_longName)),
              );
              expect(name.maxLines, 1);
              expect(name.overflow, TextOverflow.ellipsis);
              expect(tester.takeException(), isNull);
              await openMenu(tester);
              expect(menuItem('hold'), findsOneWidget);
              expect(menuItem('held'), findsOneWidget);
              expect(menuItem('clear'), findsOneWidget);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
              await tester.pumpAndSettle();
            },
          );
        }
      }
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'owner toolbar at scale $scale omits staff subtitle and its extra height',
      (tester) async {
        final staffContainer = await pump(tester, scale: scale);
        final staffDatabase = staffContainer.read(databaseProvider);
        final staffToolbarHeight = tester
            .widget<AppBar>(find.byType(AppBar))
            .toolbarHeight!;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await staffDatabase.close();
        await pump(tester, scale: scale, owner: true);
        final bar = find.byType(AppBar);
        final appBar = tester.widget<AppBar>(bar);
        expect(
          find.descendant(of: bar, matching: find.byType(StaffBadge)),
          findsNothing,
        );
        expect(
          find.descendant(of: bar, matching: find.text(_longName)),
          findsNothing,
        );
        expect(
          find.descendant(of: bar, matching: find.text('Sell')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: bar, matching: find.byTooltip('Scan barcode')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: bar,
            matching: find.byIcon(Icons.notifications_none),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: bar, matching: find.byTooltip('More actions')),
          findsOneWidget,
        );
        expect(appBar.actions, hasLength(3));
        expect(appBar.toolbarHeight, lessThanOrEqualTo(staffToolbarHeight));
        if (scale == 1) {
          expect(appBar.toolbarHeight, kToolbarHeight);
        } else {
          expect(appBar.toolbarHeight, lessThan(staffToolbarHeight));
        }
        final title = tester.widget<Column>(find.byWidget(appBar.title!));
        expect(title.children, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'empty cart disables all sale actions while leaving scanner and notifications available',
    (tester) async {
      final c = await pump(tester);
      await openMenu(tester);
      for (final value in ['hold', 'held', 'clear']) {
        expect(
          tester.widget<PopupMenuItem<String>>(menuItem(value)).enabled,
          isFalse,
        );
      }
      await tester.tap(menuItem('hold'));
      await tester.pumpAndSettle();
      expect(c.read(cartProvider).isEmpty, isTrue);
      expect(c.read(heldSalesProvider), isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('Hold parks the cart and exposes the current held count', (
    tester,
  ) async {
    final c = await pump(tester);
    c.read(cartProvider.notifier).addProduct(_row(1).product);
    c.read(cartProvider.notifier).addProduct(_row(1).product);
    await tester.pumpAndSettle();
    await openMenu(tester);
    expect(
      tester.widget<PopupMenuItem<String>>(menuItem('hold')).enabled,
      isTrue,
    );
    await tester.tap(menuItem('hold'));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).isEmpty, isTrue);
    final held = c.read(heldSalesProvider);
    expect(held, hasLength(1));
    expect(held.single.cart.lines.single.product.id, 'p1');
    expect(held.single.itemCount, 2);
    await openMenu(tester);
    expect(
      tester.widget<PopupMenuItem<String>>(menuItem('held')).enabled,
      isTrue,
    );
    expect(
      find.descendant(of: menuItem('held'), matching: find.textContaining('1')),
      findsOneWidget,
    );
    expect(
      tester.widget<PopupMenuItem<String>>(menuItem('hold')).enabled,
      isFalse,
    );
    expect(
      tester.widget<PopupMenuItem<String>>(menuItem('clear')).enabled,
      isFalse,
    );
  });

  testWidgets(
    'Held menu resumes the chosen sale and parks the existing active cart',
    (tester) async {
      final c = await pump(tester, size: const Size(430, 1000));
      c.read(cartProvider.notifier).addProduct(_row(1).product);
      c.read(heldSalesProvider.notifier).hold(c.read(cartProvider));
      c.read(cartProvider.notifier).clear();
      c.read(cartProvider.notifier).addProduct(_row(2).product);
      c.read(cartProvider.notifier).addProduct(_row(2).product);
      await tester.pumpAndSettle();
      await openMenu(tester);
      await tester.tap(menuItem('held'));
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, 'Product 1');
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(c.read(cartProvider).lines.single.product.id, 'p1');
      expect(c.read(cartProvider).itemCount, 1);
      final held = c.read(heldSalesProvider);
      expect(held, hasLength(1));
      expect(held.single.cart.lines.single.product.id, 'p2');
      expect(held.single.itemCount, 2);
      expect(tile, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Clear requires confirmation and cancel preserves the sale', (
    tester,
  ) async {
    final c = await pump(tester);
    c.read(cartProvider.notifier).addProduct(_row(1).product);
    await tester.pumpAndSettle();
    await openMenu(tester);
    await tester.tap(menuItem('clear'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(c.read(cartProvider).itemCount, 1);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).itemCount, 1);
    await openMenu(tester);
    await tester.tap(menuItem('clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(c.read(cartProvider).isEmpty, isTrue);
    expect(c.read(heldSalesProvider), isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
