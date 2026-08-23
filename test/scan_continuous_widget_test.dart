import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mm_pos/features/sell/barcode_scanner_screen.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// Continuous scanning (owner request): the scanner stays open and fires
/// for every scan — camera/HID — until Done is tapped, instead of closing
/// after each item.
Future<void> _pump(WidgetTester tester, List<String> codes) async {
  // Reset by the caller (finally) — flutter_test fails a run that leaves
  // foundation debug overrides set.
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BarcodeScannerScreen.continuous(onCode: codes.add),
    ),
  );
  await tester.pumpAndSettle();
}

void _type(String text) {
  for (final ch in text.split('')) {
    HardwareKeyboard.instance.handleKeyEvent(
      KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId),
        character: ch,
        timeStamp: Duration.zero,
      ),
    );
  }
}

void main() {
  testWidgets('continuous: HID scans fire per code and the screen stays '
      'open; Done pops it', (tester) async {
    final codes = <String>[];
    try {
      await _pump(tester, codes);

    // Simulate a scanner-gun burst: digits + Enter terminator. The screen
    // must remain open so more scans can follow.
    _type('123456');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(codes, ['123456']);
    expect(find.byType(BarcodeScannerScreen), findsOneWidget);

    _type('654321');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(codes, ['123456', '654321'],
        reason: 'second scan fires without re-opening anything');
    expect(find.byType(BarcodeScannerScreen), findsOneWidget);

        // A rapid DUPLICATE burst of the same code (camera re-fire while the
      // barcode sits in frame) is swallowed — exactly ONE addition.
      _type('123456');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(codes.length, 2,
          reason: 'same code within the cooldown window is suppressed');

    // Done closes the session.
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();
      expect(find.byType(BarcodeScannerScreen), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
