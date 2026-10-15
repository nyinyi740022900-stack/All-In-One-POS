import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/currency_def.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/features/analytics/analytics_calculator.dart';
import 'package:mm_pos/features/analytics/analytics_providers.dart';
import 'package:mm_pos/features/analytics/analytics_screen.dart';
import 'package:mm_pos/features/inventory/inventory_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_status.dart';
import 'package:mm_pos/features/staff/owner_permission.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// A Premium shop, so the glance strip gets its period-over-period line.
class _PremiumLicense extends LicenseController {
  _PremiumLicense(super.ref) {
    state = LicenseState(
      loading: false,
      license: CachedLicense(
        key: 'PREMIUM',
        shopId: 'overflow-test',
        plan: LicensePlan.yearly,
        expiresAt: DateTime(2027),
        activatedAt: DateTime(2026),
        lastVerifiedAt: DateTime(2026),
        deviceId: 'phone',
      ),
      status: const LicenseStatus(kind: LicenseStatusKind.active),
    );
  }
}

const _empty = AnalyticsSummary(
  revenue: 0,
  salesCount: 0,
  discount: 0,
  cost: 0,
  stockValue: 0,
  expenses: 0,
  creditSales: 0,
  creditOutstanding: 0,
  daily: [],
  topProducts: [],
  salesByStaff: [],
);

const _withSales = AnalyticsSummary(
  revenue: 1000,
  salesCount: 1,
  discount: 0,
  cost: 400,
  stockValue: 0,
  expenses: 0,
  creditSales: 0,
  creditOutstanding: 0,
  daily: [],
  topProducts: [],
  salesByStaff: [],
);

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required AnalyticsSummary summary,
  AnalyticsSummary? previous,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) async {
  final c = ProviderContainer(
    overrides: [
      licenseControllerProvider.overrideWith(_PremiumLicense.new),
      hasResolvedOwnerCapabilityProvider(
        OwnerCapability.analytics,
      ).overrideWithValue(true),
      shopCurrencyProvider.overrideWithValue(CurrencyDef.mmk),
      trackStockProvider.overrideWith((ref) => Stream.value(false)),
      lowStockCountProvider.overrideWithValue(0),
      analyticsSummaryProvider.overrideWith((ref) async => summary),
      if (previous != null)
        analyticsPreviousSummaryProvider.overrideWith((ref) async => previous),
    ],
  );
  addTearDown(c.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const AnalyticsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // A phone, not the 800x600 test default: both overflows only appeared once
  // the three glance cells were a third of a real phone's width.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1206, 2622);
    view.devicePixelRatio = 3.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  testWidgets('empty revenue chart is not clipped by a fixed-height box', (
    tester,
  ) async {
    // Regression: the chart slot was a SizedBox(height: 160) and the empty
    // state inside it is ~167 tall, so every shop with no sales in the period
    // — a brand-new shop on day one — saw a 7px overflow stripe.
    await _pumpDashboard(tester, summary: _empty);
    final l = AppLocalizations.of(tester.element(find.byType(AnalyticsScreen)));
    expect(find.text(l.analyticsNoData), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty chart survives a large system font', (tester) async {
    await _pumpDashboard(tester, summary: _empty, textScale: 1.6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glance strip fits its period-over-period line', (tester) async {
    // Regression: the trend label wrapped at the real cell width but
    // IntrinsicHeight measured it unbounded (one line), overflowing the row
    // by 44px on the 7-day and 30-day ranges.
    await _pumpDashboard(
      tester,
      summary: _withSales,
      previous: const AnalyticsSummary(
        revenue: 500000,
        salesCount: 20,
        discount: 0,
        cost: 0,
        stockValue: 0,
        expenses: 0,
        creditSales: 0,
        creditOutstanding: 0,
        daily: [],
        topProducts: [],
        salesByStaff: [],
      ),
    );
    expect(find.textContaining('%'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glance strip fits its trend line in Myanmar at a large font', (
    tester,
  ) async {
    await _pumpDashboard(
      tester,
      summary: _withSales,
      previous: _withSales,
      locale: const Locale('my'),
      textScale: 1.6,
    );
    expect(tester.takeException(), isNull);
  });
}
