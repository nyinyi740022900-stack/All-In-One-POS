import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/admin/admin_api.dart';
import 'package:mm_pos/admin/admin_dashboard_screen.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/core/widgets/app_widgets.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// Serves empty dashboard lists; never touches Supabase.
class _FakeApi extends AdminApi {
  @override
  Future<List<Map<String, dynamic>>> listLicenses() async => const [];
  @override
  Future<List<Map<String, dynamic>>> listRequests() async => const [];
  @override
  Future<List<Map<String, dynamic>>> listEvents() async => const [];
  @override
  Future<List<Map<String, dynamic>>> listShops({bool archived = false}) async =>
      const [];
  @override
  Future<Map<String, String>> getConfig() async => const {};
}

Future<void> _openDashboard(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: AppTheme.light(localeCode: 'en'),
      home: AdminDashboardScreen(api: _FakeApi(), onSignedOut: () {}),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // The KPI grid's tile height used to be arithmetic over font sizes copied
  // out of the theme; when titleLarge moved 19 → 20 px, "Manual payments this
  // month" overflowed its Column by 0.55 px. The height is now measured.
  for (final (name, size, scale) in [
    ('3 columns at 1280x900', const Size(1280, 900), 1.0),
    ('2 columns at 900x900', const Size(900, 900), 1.0),
    ('3 columns at 1.3x text', const Size(1280, 900), 1.3),
  ]) {
    testWidgets('the Dashboard KPI tiles fit: $name', (tester) async {
      await _openDashboard(tester, size: size, textScale: scale);
      expect(find.byType(StatCard), findsWidgets);
      expect(find.text('Manual payments this month'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
