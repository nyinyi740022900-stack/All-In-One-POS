import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/core/widgets/numeric_keypad.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/invoices/invoices_screen.dart';
import 'package:mm_pos/features/orders/orders_screen.dart';
import 'package:mm_pos/features/sell/sales_providers.dart';
import 'package:mm_pos/features/credit/credit_providers.dart';
import 'package:mm_pos/features/orders/orders_providers.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

Sale _sale(
  String id, {
  required DateTime at,
  int total = 10000,
  int paid = 0,
  String method = 'cash',
}) =>
    Sale(
      id: id,
      shopId: 'shop-1',
      invoiceNo: 'INV-$id',
      subtotal: total,
      discount: 0,
      total: total,
      paid: paid,
      changeDue: 0,
      paymentMethod: method,
      customerName: 'Customer $id',
      finalizedAt: at,
      createdAt: at,
      updatedAt: at,
      isDeleted: false,
      dirty: false,
    );

Order _order({
  String id = 'ord-1',
  DateTime? at,
}) {
  final t = at ?? DateTime(2026, 8, 10, 9, 30);
  return Order(
    id: id,
    shopId: 'shop-1',
    orderNo: 'ORD-20260810-001',
    channel: 'viber',
    status: 'new',
    customerName: 'Daw Mi',
    deliveryFee: 2000,
    itemsTotal: 15000,
    paymentStatus: 'unpaid',
    createdAt: t,
    updatedAt: t,
    isDeleted: false,
    dirty: false,
  );
}

Future<void> _pumpInvoices(
  WidgetTester tester, {
  required List<Sale> sales,
  Map<String, int> owedBySale = const {},
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        salesStreamProvider.overrideWith((ref) => Stream.value(sales)),
        creditOwedBySaleProvider.overrideWith((ref) => owedBySale),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: InvoicesScreen(embedded: true)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('invoices ledger groups by day with daily totals', (
    tester,
  ) async {
    // Two sales on Aug 10, one on Aug 9 — stream arrives newest-first.
    final sales = [
      _sale('c', at: DateTime(2026, 8, 10, 13, 0), total: 8000),
      _sale('b', at: DateTime(2026, 8, 10, 9, 15), total: 12000),
      _sale(
        'a',
        at: DateTime(2026, 8, 9, 18, 0),
        total: 5000,
        paid: 2000,
        method: 'credit',
      ),
    ];
    await _pumpInvoices(tester, sales: sales, owedBySale: {'a': 3000});

    // One header per day, in newest-first order.
    expect(find.text('10/08/2026'), findsOneWidget);
    expect(find.text('09/08/2026'), findsOneWidget);

    // Daily net totals: 8,000 + 12,000 on the 10th; 5,000 on the 9th.
    expect(find.textContaining('20,000'), findsOneWidget);
    expect(find.textContaining('5,000'), findsWidgets);

    // The day headers sit above their rows, not inside a flat list.
    expect(find.byType(ListTile), findsNWidgets(3));
  });

  testWidgets('owed figure uses the warning tone, matching the credit pill', (
    tester,
  ) async {
    final sales = [
      _sale(
        'a',
        at: DateTime(2026, 8, 10, 18, 0),
        total: 5000,
        paid: 2000,
        method: 'credit',
      ),
    ];
    await _pumpInvoices(tester, sales: sales, owedBySale: {'a': 3000});

    final owedText = tester
        .widgetList<Text>(find.textContaining('3,000'))
        .firstWhere((t) => t.style?.color != null);
    final context = tester.element(find.widgetWithText(ListTile, 'INV-a').first);
    expect(owedText.style?.color, AppColors.of(context).warning);
  });

  testWidgets('invoices ledger renders in Myanmar without layout errors', (
    tester,
  ) async {
    final sales = [
      _sale('a', at: DateTime(2026, 8, 10, 9, 15), total: 12000),
    ];
    await _pumpInvoices(
      tester,
      sales: sales,
      locale: const Locale('my'),
    );
    // Numeric day headers are locale-independent.
    expect(find.text('10/08/2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invoices ledger survives 1.3x text scale (no overflow)', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final sales = [
      _sale('b', at: DateTime(2026, 8, 10, 13, 0), total: 8000),
      _sale(
        'a',
        at: DateTime(2026, 8, 9, 18, 0),
        total: 5000,
        paid: 2000,
        method: 'credit',
      ),
    ];
    await _pumpInvoices(tester, sales: sales, owedBySale: {'a': 3000});
    expect(tester.takeException(), isNull);
  });

  testWidgets('order card shows when the order came in', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ordersStreamProvider.overrideWith(
            (ref) => Stream.value([_order()]),
          ),
          salesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: OrdersScreen(embedded: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('ORD-20260810-001 · 10/08 09:30'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('numeric keypad reports every key including 00', (tester) async {
    final digits = <String>[];
    var backspaces = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NumericKeypad(
            onDigit: digits.add,
            onBackspace: () => backspaces++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('1'));
    await tester.tap(find.text('00'));
    await tester.tap(find.text('0'));
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();

    expect(digits, ['1', '00', '0']);
    expect(backspaces, 1);
  });
}
