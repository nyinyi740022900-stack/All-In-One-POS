import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
import 'package:mm_pos/features/inventory/inventory_screen.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_status.dart';
import 'package:mm_pos/features/notifications/notification_center_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/sell/cart.dart';
import 'package:mm_pos/features/sell/checkout_sheet.dart';
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
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(360, 800),
    double scale = 1,
    List<ProductWithStock>? rows,
    bool dark = false,
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
          isEffectiveOwnerProvider.overrideWith((ref) => true),
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
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(screen.runtimeType).first),
    );
  }

  testWidgets('empty category filter explains no matches and can be cleared', (
    tester,
  ) async {
    final c = await pump(tester, const InventoryScreen());
    c.read(inventoryCategoryProvider.notifier).state = 'missing';
    await tester.pumpAndSettle();
    expect(find.text('No products yet. Add your first product.'), findsNothing);
    expect(find.text('No products match your filters.'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(c.read(inventoryCategoryProvider), isNull);
    expect(find.text('Product 1'), findsOneWidget);
  });

  testWidgets('clear filters resets search, category and low stock together', (
    tester,
  ) async {
    final c = await pump(tester, const InventoryScreen());
    c.read(inventorySearchProvider.notifier).state = 'missing';
    c.read(inventoryCategoryProvider.notifier).state = 'missing';
    c.read(inventoryLowStockOnlyProvider.notifier).state = true;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(c.read(inventorySearchProvider), isEmpty);
    expect(c.read(inventoryCategoryProvider), isNull);
    expect(c.read(inventoryLowStockOnlyProvider), isFalse);
    expect(find.text('Product 1'), findsOneWidget);
  });

  testWidgets('inventory exports live under a labelled menu on phones', (
    tester,
  ) async {
    await pump(tester, const InventoryScreen());
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byTooltip('More actions'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.byIcon(Icons.table_chart_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('last tablet product clears the Add button', (tester) async {
    await pump(
      tester,
      const InventoryScreen(),
      size: const Size(820, 900),
      rows: List.generate(30, _row),
    );
    final grid = find.byType(GridView);
    await tester.drag(grid, const Offset(0, -6000));
    await tester.pumpAndSettle();
    final last = tester.getRect(
      find
          .ancestor(of: find.text('Product 29'), matching: find.byType(Card))
          .first,
    );
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(last.overlaps(fab), isFalse);
  });

  for (final (width, scale) in [(360.0, 1.0), (430.0, 1.3), (430.0, 2.0)]) {
    testWidgets(
      'sell products use readable rows at width $width scale $scale',
      (tester) async {
        await pump(
          tester,
          const SellScreen(),
          size: Size(width, 900),
          scale: scale,
        );
        final first = tester.getTopLeft(find.text('Product 1'));
        final second = tester.getTopLeft(find.text('Product 2'));
        expect(second.dy, greaterThan(first.dy));
        expect(second.dx, closeTo(first.dx, 0.1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final locale in [const Locale('en'), const Locale('my')]) {
    for (final dark in [false, true]) {
      testWidgets(
        'large text ${locale.languageCode} ${dark ? "dark" : "light"} sell with stock cues and cart',
        (tester) async {
          final row = _row(1);
          final c = await pump(
            tester,
            const SellScreen(),
            size: const Size(375, 900),
            scale: 2,
            locale: locale,
            dark: dark,
            rows: [
              ProductWithStock(
                product: row.product.copyWith(
                  name: 'အရည်အသွေးမြင့် ကော်ဖီနှင့် နို့မှုန့်',
                ),
                quantity: 2,
                reorderLevel: 5,
              ),
            ],
          );
          c.read(cartProvider.notifier).addProduct(row.product);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets(
        'large text ${locale.languageCode} ${dark ? "dark" : "light"} inventory stays readable',
        (tester) async {
          await pump(
            tester,
            const InventoryScreen(),
            size: const Size(375, 900),
            scale: 2,
            locale: locale,
            dark: dark,
          );
          expect(tester.takeException(), isNull);
        },
      );
      testWidgets(
        'large text ${locale.languageCode} ${dark ? "dark" : "light"} checkout keeps its confirm amount readable',
        (tester) async {
          final c = await pump(
            tester,
            const Scaffold(body: CheckoutSheet()),
            size: const Size(375, 900),
            scale: 2,
            locale: locale,
            dark: dark,
          );
          c.read(cartProvider.notifier).addProduct(_row(1).product);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('credit checkout focuses the name and retains an inline error', (
    tester,
  ) async {
    final c = await pump(
      tester,
      const Scaffold(body: CheckoutSheet()),
      size: const Size(430, 1000),
    );
    c.read(cartProvider.notifier).addProduct(_row(1).product);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm sale'));
    await tester.pumpAndSettle();
    final field = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((f) => f.decoration?.labelText == 'Customer name *');
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.decoration!.errorText, isNotNull);
    await tester.enterText(find.byWidget(field), 'Daw Mya');
    await tester.pumpAndSettle();
    final updated = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((f) => f.decoration?.labelText == 'Customer name *');
    expect(updated.decoration!.errorText, isNull);
    expect(tester.takeException(), isNull);
    // Dispose checkout before the harness closes its in-memory database.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
