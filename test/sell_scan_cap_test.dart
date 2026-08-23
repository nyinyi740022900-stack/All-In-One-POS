import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/domain/product_with_stock.dart';
import 'package:mm_pos/features/inventory/inventory_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/sell/cart.dart';
import 'package:mm_pos/features/sell/sell_barcode.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// Regression coverage for audit QA-H3: the barcode/scan path must enforce
/// the SAME per-product stock cap the Sell grid enforces — 8 scans of a
/// product with 5 on the shelf must stop at 5, not oversell into negative
/// stock.
void main() {
  // Captured from the Consumer's ref once the tree is built; used to wait
  // for the overridden streams' first emissions before scanning.
  List<ProductWithStock>? Function()? catalogueRead;
  bool? Function()? trackRead;

  ProductWithStock stock(int qty) => ProductWithStock(
        product: Product(
          id: 'p1',
          shopId: 'shop-1',
          name: 'Coke',
          barcode: '1234567890',
          costPrice: 500,
          salePrice: 700,
          unit: 'pcs',
          isActive: true,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          isDeleted: false,
          dirty: false,
        ),
        quantity: qty,
        reorderLevel: 0,
      );

  Future<void> pumpHarness(WidgetTester tester, int shelfQty, bool track) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        productsStreamProvider.overrideWith((ref) => Stream.value([stock(shelfQty)])),
        trackStockProvider.overrideWith((ref) => Stream.value(track)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            final count = ref.watch(cartProvider.select((c) => c.itemCount));
            // WATCH both streams so the lazy StreamProviders initialize at
            // first build — a read-only harness left them null until the
            // first scan initialized them mid-loop, swallowing scan #1.
            final products = ref.watch(productsStreamProvider).valueOrNull;
            final trackNow = ref.watch(trackStockProvider).valueOrNull;
            catalogueRead = () => products;
            trackRead = () => trackNow;
            return Column(children: [
              Text('count=$count'),
              TextButton(
                // Simulates the scanner's event-handler context (never a
                // widget build); one event-turn per scan like real hardware.
                onPressed: () async {
                  final l = AppLocalizations.of(context);
                  for (var i = 0; i < 8; i++) {
                    applyScannedSellCode(context, ref, l, '1234567890');
                    await Future<void>.delayed(Duration.zero);
                  }
                },
                child: const Text('scan8'),
              ),
            ]);
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // The overridden stream emits asynchronously — advance the fake clock
    // until the catalogue has actually landed so every scan matches.
    var waited = 0;
    while (catalogueRead?.call() == null && waited < 200) {
      await tester.pump(const Duration(milliseconds: 10));
      waited++;
    }
    expect(catalogueRead?.call(), isNotNull,
        reason: 'harness: catalogue stream never emitted');
    var trackWaited = 0;
    while (trackRead?.call() != track && trackWaited < 200) {
      await tester.pump(const Duration(milliseconds: 10));
      trackWaited++;
    }
    expect(trackRead?.call(), track,
        reason: 'harness: trackStock stream never emitted');
  }

  testWidgets('8 scans of a 5-unit shelf cap the cart at 5', (tester) async {
    await pumpHarness(tester, 5, true);
    await tester.tap(find.text('scan8'));
    await tester.pumpAndSettle();
    expect(find.text('count=5'), findsOneWidget,
        reason: 'scan path must honor the same maxQty cap as grid taps '
            '(previously uncapped → negative stock at checkout)');
    expect(find.text('count=6'), findsNothing);
  });

  testWidgets('trackStock off removes the cap (invoice-only shops)',
      (tester) async {
    await pumpHarness(tester, 5, false);
    await tester.tap(find.text('scan8'));
    await tester.pumpAndSettle();
    expect(find.text('count=8'), findsOneWidget);
  });
}
