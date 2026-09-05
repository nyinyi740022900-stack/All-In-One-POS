import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/notifications/notification_center_providers.dart';
import 'package:mm_pos/app.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/domain/product_with_stock.dart';
import 'package:mm_pos/features/inventory/inventory_providers.dart';
import 'package:mm_pos/features/orders/orders_providers.dart';
import 'package:mm_pos/features/account/branch_providers.dart';
import 'package:mm_pos/features/onboarding/operating_mode_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/features/sell/sell_screen.dart';

void main() {
  testWidgets('app boots to the sell screen with 5-tab bottom navigation',
      (tester) async {
    // Phone-sized viewport so the responsive shell uses the bottom
    // NavigationBar (the default 800x600 surface shows the tablet rail).
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // Skip first-run onboarding + mode migrate — this test verifies the main
    // tabbed shell.
    final settings = SettingsRepository(db);
    await settings.markOnboardingComplete();
    await settings.setOperatingMode(SettingsRepository.operatingModeOffline);
    await settings.confirmOperatingMode();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          // Emit immediately so no loading spinner animates forever in the
          // fake test clock (which would make pumpAndSettle never settle).
          productsStreamProvider
              .overrideWith((ref) => Stream.value(<ProductWithStock>[])),
          // Single-value streams so the Drift watches (settings, categories)
          // don't leave a query-stream subscription pending under the fake
          // clock when the provider scope tears down.
          trackStockProvider.overrideWith((ref) => Stream.value(true)),
          categoriesStreamProvider
              .overrideWith((ref) => Stream.value(<Category>[])),
          // The Orders/Invoices hub is built eagerly by the IndexedStack
          // shell, and its TabBarView builds the Orders sub-tab (index 0)
          // right away; give it a single-value stream so its Drift watch
          // doesn't stay pending. The Invoices sub-tab is NOT built until
          // selected, so `salesStreamProvider` needs no override here.
          ordersStreamProvider.overrideWith((ref) => Stream.value(<Order>[])),
          // The Sell app bar's notification bell reads this straight from
          // Drift. Left live, its subscription is cancelled at teardown and
          // Drift schedules a zero-duration cleanup timer, which trips the
          // "Timer is still pending" invariant — same reason every other
          // Drift-backed stream on this screen is overridden here.
          notificationUnreadCountProvider.overrideWith((ref) => Stream.value(0)),
          // The router's role-based tab filter watches this — single-value
          // so it doesn't leave a pending Drift stream under the fake clock.
          staffRoleProvider.overrideWith((ref) => Stream.value('owner')),
          activeStaffIdProvider.overrideWith((ref) => Stream.value(null)),
          branchSwitchRecoveryProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
          // The daily gate is universal now (every shop, every plan) — this
          // test verifies the main tabbed shell, not the gate itself.
          dailyGateNeededProvider.overrideWith((ref) async => false),
        ],
        child: const MmPosApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SellScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    // 5, not 6: Orders + Invoices share one destination (sub-tabs in the hub).
    expect(find.byType(NavigationDestination), findsNWidgets(5));
  });
}
