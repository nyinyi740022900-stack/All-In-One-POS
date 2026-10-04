import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/inventory/stock_adjust_dialog.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// The stock dialog opens on "Count is now" pre-filled with the current stock
/// and the "Recount" reason; "+ Received" is the explicit way to add units.
void main() {
  Future<AppDatabase> open(WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () => showStockAdjustDialog(
                  context,
                  ref,
                  productId: 'p1',
                  productName: 'Cola',
                  currentQuantity: 21,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('defaults to Count is now, prefilled, reason Recount',
      (tester) async {
    await open(tester);
    expect(find.text('Count is now'), findsWidgets);
    expect(find.text('Recount'), findsOneWidget);
    expect(find.text('Damaged'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, '21');
  });

  testWidgets('+ Received clears the field and drops the reason picker',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('+ Received'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, '');
    expect(find.text('Recount'), findsNothing);
    expect(find.text('Unit cost (optional)'), findsOneWidget);
  });

  testWidgets('saving an unchanged count is rejected, not written',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid quantity'), findsOneWidget);
  });
}
