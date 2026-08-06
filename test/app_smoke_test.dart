import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/app.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/domain/product_with_stock.dart';
import 'package:mm_pos/features/inventory/inventory_providers.dart';
import 'package:mm_pos/features/orders/orders_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/sell/sell_screen.dart';

void main() {
  testWidgets('app boots to the sell screen with 6-tab bottom navigation',
      (tester) async {
    // Phone-sized viewport so the responsive shell uses the bottom
    // NavigationBar (the default 800x600 surface shows the tablet rail).
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // Skip first-run onboarding — this test verifies the main tabbed shell.
    await SettingsRepository(db).markOnboardingComplete();

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
          // The Orders tab is built eagerly by the IndexedStack shell; give it
          // a single-value stream so its Drift watch doesn't stay pending.
          ordersStreamProvider.overrideWith((ref) => Stream.value(<Order>[])),
        ],
        child: const MmPosApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SellScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(6));
  });
}
