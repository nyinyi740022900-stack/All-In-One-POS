import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/build_flags.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/features/settings/help_guide_screen.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

Future<AppLocalizations> _pump(WidgetTester tester, Locale locale) async {
  // A fresh tree each time, so an ExpansionTile opened under one locale
  // isn't still open (and closed again by the next tap) under the other.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HelpGuideScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(HelpGuideScreen)));
}

void main() {
  for (final locale in const [Locale('en'), Locale('my')]) {
    testWidgets(
      'guide lists every section in tab order (${locale.languageCode})',
      (tester) async {
        final l = await _pump(tester, locale);
        final titles = tester
            .widgetList<ExpansionTile>(find.byType(ExpansionTile))
            .map((t) => (t.title as Text).data)
            .toList();
        // Orders tab = Invoices then Social Orders; Shop tab = Daily then setup.
        expect(titles, [
          l.helpGuideSellTitle,
          l.helpGuideInventoryTitle,
          l.helpGuideInvoicesTitle,
          l.helpGuideOrdersTitle,
          l.helpGuideAnalyticsTitle,
          l.helpGuideDailyTitle,
          l.helpGuideSettingsTitle,
        ]);
      },
    );
  }

  testWidgets('store build guide never says where to pay for Premium', (
    tester,
  ) async {
    // App Store / Play builds must not point the owner at a payment path
    // (see kCommerceUiEnabled). The Shop section is the only one that
    // mentions buying Premium, so it carries the commerce-free variant.
    expect(kCommerceUiEnabled, isFalse);
    for (final locale in const [Locale('en'), Locale('my')]) {
      final l = await _pump(tester, locale);
      await tester.ensureVisible(find.text(l.helpGuideSettingsTitle));
      await tester.tap(find.text(l.helpGuideSettingsTitle));
      await tester.pumpAndSettle();
      expect(find.text(l.helpGuideSettingsBodyNoCommerce), findsOneWidget);
      expect(find.text(l.helpGuideSettingsBody), findsNothing);
      final body = l.helpGuideSettingsBodyNoCommerce.toLowerCase();
      expect(body.contains('website'), isFalse);
      expect(body.contains('viber'), isFalse);
    }
  });
}
