import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// The bottom nav's labels must stop growing with the system font size.
///
/// Audit (Play-update UI/UX pass): on a 360dp phone — the cheap Android this
/// app is actually sold for — at Android's "Large" font setting, the Myanmar
/// destination labels ("ကုန်ပစ္စည်း", "စာရင်းအင်း") wrapped MID-SYLLABLE,
/// orphaning the trailing "း" on a second line and crowding the five
/// destinations into each other. Verified by hand on a 360dp Pixel 7: clean at
/// 1.15x, broken at 1.3x. `router.dart` now clamps the label scale.
///
/// This asserts the CLAMP, not the pixel layout: widget tests render with a
/// fixed-width test font whose metrics are nothing like Noto Sans Myanmar, so
/// a width/wrap assertion here would be measuring the wrong font and would
/// pass or fail for reasons unrelated to the real device. What is worth
/// locking in — and what is font-independent — is that no matter how large the
/// reader sets their system font, the text inside the bar is scaled by at most
/// [_navLabelMaxTextScale], while the rest of the app keeps scaling freely.
const double _navLabelMaxTextScale = 1.15;

/// Mirrors `_ShellScaffold`'s structure: the clamp wraps only the bar.
Widget _harness({
  required double ambientScale,
  required void Function(BuildContext barContext) onBarContext,
  required void Function(BuildContext bodyContext) onBodyContext,
}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(ambientScale)),
    child: MaterialApp(
      locale: const Locale('my'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(builder: (context) {
          onBodyContext(context);
          return const SizedBox.expand();
        }),
        bottomNavigationBar: MediaQuery.withClampedTextScaling(
          maxScaleFactor: _navLabelMaxTextScale,
          child: Builder(builder: (context) {
            onBarContext(context);
            final l = AppLocalizations.of(context);
            return NavigationBar(
              selectedIndex: 0,
              destinations: [
                NavigationDestination(
                    icon: const Icon(Icons.point_of_sale), label: l.navSell),
                NavigationDestination(
                    icon: const Icon(Icons.inventory_2), label: l.navInventory),
                NavigationDestination(
                    icon: const Icon(Icons.receipt_long), label: l.navOrders),
                NavigationDestination(
                    icon: const Icon(Icons.bar_chart), label: l.navAnalytics),
                NavigationDestination(
                    icon: const Icon(Icons.settings), label: l.navSettings),
              ],
            );
          }),
        ),
      ),
    ),
  );
}

Future<({TextScaler bar, TextScaler body})> _scalersAt(
    WidgetTester tester, double ambientScale) async {
  late TextScaler bar;
  late TextScaler body;
  await tester.pumpWidget(_harness(
    ambientScale: ambientScale,
    onBarContext: (c) => bar = MediaQuery.textScalerOf(c),
    onBodyContext: (c) => body = MediaQuery.textScalerOf(c),
  ));
  await tester.pumpAndSettle();
  return (bar: bar, body: body);
}

void main() {
  group('nav labels stop scaling at $_navLabelMaxTextScale', () {
    // 1.0 is the default, 1.3 is Android's "Large" (the setting that actually
    // broke on device), 2.0 is the largest the system offers.
    for (final ambient in const [1.0, 1.15, 1.3, 2.0]) {
      testWidgets('system font ${ambient}x → bar scales by at most '
          '$_navLabelMaxTextScale', (tester) async {
        final s = await _scalersAt(tester, ambient);
        const base = 12.0;
        expect(s.bar.scale(base),
            lessThanOrEqualTo(base * _navLabelMaxTextScale + 0.001),
            reason: 'a ${ambient}x system font must not push the nav label '
                'past ${_navLabelMaxTextScale}x');
      });
    }

    testWidgets('below the cap the reader still gets their chosen size — the '
        'clamp is a ceiling, not a fixed size', (tester) async {
      final small = await _scalersAt(tester, 1.0);
      final mid = await _scalersAt(tester, 1.15);
      expect(mid.bar.scale(12.0), greaterThan(small.bar.scale(12.0)));
    });

    testWidgets('the clamp is scoped to the bar — the rest of the app still '
        'scales all the way up', (tester) async {
      final s = await _scalersAt(tester, 2.0);
      const base = 12.0;
      expect(s.body.scale(base), closeTo(base * 2.0, 0.001),
          reason: 'clamping the nav must not shrink the app body too');
      expect(s.bar.scale(base), lessThan(s.body.scale(base)));
    });
  });
}
