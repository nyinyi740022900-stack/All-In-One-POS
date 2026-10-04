import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/orders/order_detail_sheet.dart';
import 'package:mm_pos/features/orders/order_labels.dart';
import 'package:mm_pos/features/orders/orders_invoices_hub_screen.dart';
import 'package:mm_pos/features/orders/orders_providers.dart';
import 'package:mm_pos/features/orders/orders_screen.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/sell/sales_providers.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

Order _order(int i, {String payment = 'unpaid'}) => Order(
  id: '$i',
  shopId: 'shop',
  createdAt: DateTime(2026, 10, 3),
  updatedAt: DateTime(2026, 10, 3),
  isDeleted: false,
  dirty: false,
  orderNo: 'O$i',
  channel: 'facebook',
  status: 'delivered',
  customerName: 'Customer $i',
  deliveryFee: 0,
  itemsTotal: 100,
  paymentStatus: payment,
  saleId: 'sale-$i',
);

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, file) in [
      ('Inter', 'Inter-Regular.ttf'),
      ('NotoSansMyanmar', 'NotoSansMyanmar-Regular.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
  });

  Future<void> pump(
    WidgetTester tester, {
    required bool hub,
    required Size size,
    double scale = 1,
    Locale locale = const Locale('en'),
    bool dark = false,
    List<Order>? orders,
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
          shopIdProvider.overrideWith((ref) => 'shop'),
          ordersStreamProvider.overrideWith(
            (ref) => Stream.value(orders ?? List.generate(30, _order)),
          ),
          salesStreamProvider.overrideWith((ref) => Stream.value(<Sale>[])),
          orderItemsProvider.overrideWith((ref, id) async => <OrderItem>[]),
          shopProfileProvider.overrideWith(
            (ref) async => const ShopProfile(name: 'Test shop'),
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
          home: hub
              ? const OrdersInvoicesHubScreen(
                  initialTab: OrdersInvoicesHubScreen.ordersTab,
                )
              : const OrdersScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final hub in [false, true]) {
    for (final size in [const Size(430, 900), const Size(1024, 1000)]) {
      for (final locale in [const Locale('en'), const Locale('my')]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            'final order clears FAB and opens ${hub ? "hub" : "standalone"} ${size.width} ${locale.languageCode} $scale',
            (tester) async {
              await pump(
                tester,
                hub: hub,
                size: size,
                locale: locale,
                scale: scale,
              );
              final list = find.descendant(
                of: find.byType(OrdersScreen),
                matching: find.byType(ListView),
              );
              await tester.drag(list, const Offset(0, -20000));
              await tester.pumpAndSettle();
              final card = find.descendant(
                of: find.byKey(const ValueKey('order-29')),
                matching: find.byType(Card),
              );
              expect(
                tester.getRect(card).bottom,
                lessThan(tester.getRect(find.byType(FloatingActionButton)).top),
                reason:
                    'The final order must scroll entirely above the New order button.',
              );
              await tester.tap(card);
              await tester.pumpAndSettle();
              expect(
                tester
                    .widget<OrderDetailSheet>(find.byType(OrderDetailSheet))
                    .orderId,
                '29',
              );
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
              await tester.pump();
            },
          );
        }
      }
    }
  }

  for (final dark in [false, true]) {
    for (final payment in ['paid', 'unpaid', 'partial']) {
      testWidgets(
        'tablet selected card palette and text contrast dark=$dark payment=$payment',
        (tester) async {
          await pump(
            tester,
            hub: true,
            size: const Size(1024, 1000),
            dark: dark,
            orders: [
              _order(0, payment: payment),
              _order(1),
            ],
          );
          final row = find.byKey(const ValueKey('order-0'));
          final card = find.descendant(of: row, matching: find.byType(Card));
          final other = find.descendant(
            of: find.byKey(const ValueKey('order-1')),
            matching: find.byType(Card),
          );
          await tester.tap(card);
          await tester.pumpAndSettle();
          final context = tester.element(card);
          final theme = Theme.of(context);
          final fill = theme.colorScheme.primaryContainer;
          expect(tester.widget<Card>(card).color, fill);
          expect(tester.widget<Card>(other).color, isNull);
          final texts = find.descendant(of: row, matching: find.byType(Text));
          final labels = AppLocalizations.of(context);
          for (final text in tester.widgetList<Text>(texts)) {
            final semanticText =
                text.data == orderStatusLabel(labels, 'delivered') ||
                text.data == orderPaymentLabel(labels, payment);
            var background = fill;
            if (semanticText) {
              final plate = find
                  .ancestor(
                    of: find.byWidget(text),
                    matching: find.byType(DecoratedBox),
                  )
                  .first;
              background =
                  (tester.widget<DecoratedBox>(plate).decoration
                          as BoxDecoration)
                      .color!;
            }
            final color =
                text.style?.color ??
                DefaultTextStyle.of(
                  tester.element(find.byWidget(text)),
                ).style.color!;
            expect(
              _contrast(color, background),
              greaterThanOrEqualTo(4.5),
              reason: '${text.data} on selected card',
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  }
}
