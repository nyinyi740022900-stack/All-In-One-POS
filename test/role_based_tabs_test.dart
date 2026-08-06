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
import 'package:mm_pos/features/inventory/inventory_providers.dart';
import 'package:mm_pos/features/orders/orders_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';

/// Covers the router's role-based tab filtering: Analytics is hidden in Staff
/// mode (business-sensitive), while Settings stays visible even for Staff (the
/// only way back to Owner mode, via the PIN).
void main() {
  Future<void> pump(WidgetTester tester, {String? backendRole}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await SettingsRepository(db).markOnboardingComplete();

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
          backendAccountRoleProvider.overrideWithValue(backendRole),
        ],
        child: const MmPosApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('owner sees all 6 tabs including Analytics', (tester) async {
    await pump(tester, backendRole: 'owner');
    expect(find.byType(NavigationDestination), findsNWidgets(6));
  });

  testWidgets(
      'staff sees 5 tabs — Analytics hidden, Settings still visible',
      (tester) async {
    await pump(tester, backendRole: 'staff');
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.byIcon(Icons.bar_chart), findsNothing);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets(
      'missing backend role falls back to owner (6 tabs)', (tester) async {
    await pump(tester);
    expect(find.byType(NavigationDestination), findsNWidgets(6));
  });

  testWidgets('backend staff role keeps 5 tabs', (tester) async {
    await pump(tester, backendRole: 'staff');
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.byIcon(Icons.bar_chart), findsNothing);
  });
}
