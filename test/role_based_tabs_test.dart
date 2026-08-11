import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/app.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/domain/product_with_stock.dart';
import 'package:mm_pos/features/account/account_providers.dart';
import 'package:mm_pos/features/account/branch_providers.dart';
import 'package:mm_pos/features/inventory/inventory_providers.dart';
import 'package:mm_pos/features/orders/orders_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';

/// Covers the router's role-based tab filtering: Analytics is hidden in Staff
/// mode (business-sensitive), while Settings stays visible even for Staff (the
/// only way back to Owner mode, via the PIN).
void main() {
  Future<void> pump(WidgetTester tester, String role, {String? backendRole}) async {
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
        overrides: [
          databaseProvider.overrideWithValue(db),
          productsStreamProvider
              .overrideWith((ref) => Stream.value(<ProductWithStock>[])),
          trackStockProvider.overrideWith((ref) => Stream.value(true)),
          categoriesStreamProvider
              .overrideWith((ref) => Stream.value(<Category>[])),
          ordersStreamProvider.overrideWith((ref) => Stream.value(<Order>[])),
          staffRoleProvider.overrideWith((ref) => Stream.value(role)),
          activeStaffIdProvider.overrideWith((ref) => Stream.value(null)),
          branchSwitchRecoveryProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
          backendAccountRoleProvider.overrideWithValue(backendRole),
        ],
        child: const MmPosApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Counts are 5/4 (not 6/5) since Orders + Invoices merged into a single
  // destination with sub-tabs inside the hub screen.
  testWidgets('owner sees all 5 tabs including Analytics', (tester) async {
    await pump(tester, 'owner');
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.byIcon(Icons.bar_chart), findsOneWidget);
  });

  testWidgets(
      'staff sees 4 tabs — Analytics hidden, Settings still visible (PIN escape hatch)',
      (tester) async {
    await pump(tester, 'staff');
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.byIcon(Icons.bar_chart), findsNothing);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets(
      'backend staff role overrides local owner mode (still 4 tabs)', (tester) async {
    await pump(tester, 'owner', backendRole: 'staff');
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.byIcon(Icons.bar_chart), findsNothing);
  });
}
