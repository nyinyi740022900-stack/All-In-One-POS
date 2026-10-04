import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/currency_def.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/features/analytics/analytics_calculator.dart';
import 'package:mm_pos/features/analytics/analytics_providers.dart';
import 'package:mm_pos/features/analytics/analytics_screen.dart';
import 'package:mm_pos/features/inventory/inventory_providers.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_status.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/staff/owner_permission.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/l10n/app_localizations.dart';
import 'package:mm_pos/features/suppliers/accounts_payable.dart';
import 'package:mm_pos/features/suppliers/accounts_payable_providers.dart';
import 'package:mm_pos/features/suppliers/accounts_payable_screen.dart';
import 'package:mm_pos/features/accounts/payment_account_providers.dart';

class _FreeLicense extends LicenseController {
  _FreeLicense(super.ref) {
    state = LicenseState(
      loading: false,
      license: CachedLicense(
        key: 'FREE', shopId: 'free-test', plan: LicensePlan.free,
        expiresAt: DateTime(2026), activatedAt: DateTime(2026),
        lastVerifiedAt: DateTime(2026), deviceId: 'phone',
      ),
      status: const LicenseStatus(kind: LicenseStatusKind.active),
    );
  }
}

void main() {
  testWidgets('Free shop can open and repay an existing supplier debt', (tester) async {
    const balance = SupplierBalance(key: 'supplier-a', name: 'Rice supplier', billed: 10000, paid: 2000);
    final c = ProviderContainer(overrides: [
      licenseControllerProvider.overrideWith(_FreeLicense.new),
      shopCurrencyProvider.overrideWithValue(CurrencyDef.mmk),
      supplierBalancesProvider.overrideWithValue([balance]),
      allSupplierBalancesProvider.overrideWithValue([balance]),
      receivedPOsProvider.overrideWith((ref) => Stream.value([])),
      supplierPaymentsProvider.overrideWith((ref) => Stream.value([])),
      paymentAccountsProvider.overrideWith((ref) => Stream.value([])),
    ]);

    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(
      theme: AppTheme.light(), locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AccountsPayableScreen(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Rice supplier'), findsOneWidget);
    await tester.tap(find.text('Rice supplier'));
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(AccountsPayableSupplierScreen)));
    expect(find.text(l.apRecordPayment), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump();
  });

  testWidgets('Free owner can read sales totals without advanced profit or trends', (tester) async {
    final c = ProviderContainer(overrides: [
      licenseControllerProvider.overrideWith(_FreeLicense.new),
      hasResolvedOwnerCapabilityProvider(OwnerCapability.analytics).overrideWithValue(true),
      shopCurrencyProvider.overrideWithValue(CurrencyDef.mmk),
      trackStockProvider.overrideWith((ref) => Stream.value(false)),
      lowStockCountProvider.overrideWithValue(0),
      analyticsSummaryProvider.overrideWith((ref) async => const AnalyticsSummary(
        revenue: 12000, salesCount: 2, discount: 0, cost: 5000, stockValue: 0,
        expenses: 1000, creditSales: 1, creditOutstanding: 4000,
        daily: [], topProducts: [], salesByStaff: [],
      )),
    ]);

    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(
      theme: AppTheme.light(), locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AnalyticsScreen(),
    )));
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(AnalyticsScreen)));
    expect(find.text(l.analyticsSalesHeadline), findsOneWidget);
    expect(find.text(l.analyticsCollected), findsOneWidget);
    expect(find.text(l.analyticsOwed), findsOneWidget);
    expect(find.textContaining('12,000'), findsOneWidget);
    expect(find.textContaining('8,000'), findsOneWidget);
    expect(find.textContaining('4,000'), findsOneWidget);
    expect(find.text(l.analyticsProfitSection), findsNothing);
    expect(find.byIcon(Icons.summarize_outlined), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.pump();
  });
}
