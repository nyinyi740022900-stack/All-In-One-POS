import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/app.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/router.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/domain/product_with_stock.dart';
import 'package:mm_pos/features/account/branch_providers.dart';
import 'package:mm_pos/features/credit/credit_providers.dart';
import 'package:mm_pos/features/inventory/inventory_providers.dart';
import 'package:mm_pos/features/invoices/invoices_screen.dart';
import 'package:mm_pos/features/orders/orders_providers.dart';
import 'package:mm_pos/features/orders/orders_screen.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/sell/sales_providers.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';

/// Orders + Invoices share ONE bottom-nav destination with two sub-tabs.
/// What's pinned here is the part that would silently rot: the hub's chrome
/// (title / app-bar action / FAB) must follow the selected sub-tab, and the
/// `/invoices` deep link (used three times by analytics_screen.dart) must
/// still open the Invoices sub-tab rather than the branch's default.
void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = SettingsRepository(db);
    await settings.markOnboardingComplete();
    await settings.setOperatingMode(SettingsRepository.operatingModeOffline);
    await settings.confirmOperatingMode();

    await tester.pumpWidget(
      ProviderScope(
        // Single-value streams so nothing stays pending under the fake clock.
        overrides: [
          databaseProvider.overrideWithValue(db),
          productsStreamProvider
              .overrideWith((ref) => Stream.value(<ProductWithStock>[])),
          trackStockProvider.overrideWith((ref) => Stream.value(true)),
          categoriesStreamProvider
              .overrideWith((ref) => Stream.value(<Category>[])),
          ordersStreamProvider.overrideWith((ref) => Stream.value(<Order>[])),
          // The Invoices sub-tab's own reads: the sales ledger plus the credit
          // watches behind `creditOwedBySaleProvider`. Without these the real
          // Drift query streams stay open and leave a pending close timer once
          // the tree is torn down under the fake clock.
          salesStreamProvider.overrideWith((ref) => Stream.value(<Sale>[])),
          creditSalesProvider.overrideWith((ref) => Stream.value(<Sale>[])),
          repaymentsProvider
              .overrideWith((ref) => Stream.value(<CreditPayment>[])),
          staffRoleProvider.overrideWith((ref) => Stream.value('owner')),
          activeStaffIdProvider.overrideWith((ref) => Stream.value(null)),
          branchSwitchRecoveryProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
        ],
        child: const MmPosApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps the merged Orders destination in the bottom bar.
  Future<void> openHub(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.receipt_long));
    await tester.pumpAndSettle();
  }

  testWidgets('hub shows both sub-tabs under one nav destination',
      (tester) async {
    await pump(tester);
    await openHub(tester);

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(Tab), findsNWidgets(2));
    // Orders is the default sub-tab; Invoices is not built until selected.
    expect(find.byType(OrdersScreen), findsOneWidget);
  });

  testWidgets('chrome follows the selected sub-tab: FAB on Orders, '
      'sales-report action on Invoices', (tester) async {
    await pump(tester);
    await openHub(tester);

    // Orders: "new order" FAB, no sales-report action.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.summarize_outlined), findsNothing);

    await tester.tap(find.byType(Tab).last);
    await tester.pumpAndSettle();

    // Invoices: sales-report action, no FAB.
    expect(find.byType(InvoicesScreen), findsOneWidget);
    expect(find.byIcon(Icons.summarize_outlined), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    // ...and back again, so the swap isn't one-way.
    await tester.tap(find.byType(Tab).first);
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.summarize_outlined), findsNothing);
  });

  // Runs last on purpose: `appRouter` is a top-level singleton, so the branch
  // location this test leaves behind would otherwise bleed into the cases
  // above (they assume the branch's default `/orders`).
  testWidgets('/invoices deep link opens the Invoices sub-tab directly',
      (tester) async {
    await pump(tester);

    // What analytics_screen.dart does in three places.
    appRouter.go('/invoices');
    await tester.pumpAndSettle();

    expect(find.byType(InvoicesScreen), findsOneWidget);
    expect(find.byIcon(Icons.summarize_outlined), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    // Still one merged destination, not a resurrected sixth tab.
    expect(find.byType(NavigationDestination), findsNWidgets(5));
  });
}
