import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/admin/admin_api.dart';
import 'package:mm_pos/admin/admin_dashboard_screen.dart';
import 'package:mm_pos/admin/admin_storage_model.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/core/widgets/app_widgets.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// Serves the dashboard canned lists and counts storage fetches; never
/// touches Supabase (the client getter is only read by the real methods).
class _FakeApi extends AdminApi {
  int storageFetches = 0;
  bool fail = false;

  @override
  Future<List<Map<String, dynamic>>> listLicenses() async => const [];
  @override
  Future<List<Map<String, dynamic>>> listRequests() async => const [];
  @override
  Future<List<Map<String, dynamic>>> listEvents() async => const [];
  @override
  Future<List<Map<String, dynamic>>> listShops({bool archived = false}) async =>
      const [
        {'shop_id': 'shop-a', 'shop_name': 'Zay Shae', 'status': 'active'},
      ];
  @override
  Future<Map<String, String>> getConfig() async => const {};

  @override
  Future<StorageReport> storageReport() async {
    storageFetches++;
    if (fail) throw Exception('server_error');
    return StorageReport.fromJson({
      'database_bytes': 17 * 1024 * 1024,
      'shops': [
        {
          'shop_id': 'shop-a',
          'rows': 82,
          'bytes': 40960,
          'photos': 3,
          'photo_bytes': 600 * 1024,
        },
        {'shop_id': 'shop-gone', 'rows': 5, 'bytes': 2048},
        {'shop_id': '', 'rows': 4, 'bytes': 532},
      ],
      'unfoldered_photos': 28,
      'unfoldered_photo_bytes': 4 * 1024 * 1024,
    });
  }

  @override
  Future<OrphanPhotos> photoOrphans() async => OrphanPhotos.fromJson({
    'files': 2,
    'bytes': 300 * 1024,
    'names': ['shop-a/p-1.jpg', 'p-1784562073263.jpeg'],
  });
}

Future<void> _openStorage(WidgetTester tester, _FakeApi api) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: AppTheme.light(localeCode: 'en'),
      home: AdminDashboardScreen(api: api, onSignedOut: () {}),
    ),
  );
  await tester.pumpAndSettle();
  // The Dashboard lands first; it must render clean too (its KPI tiles once
  // overflowed by 0.55 px — see StatCard.gridExtent).
  expect(tester.takeException(), isNull);
  await tester.tap(find.text('Storage'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Storage shows the totals, each shop by name and the dry run', (
    tester,
  ) async {
    final api = _FakeApi();
    await _openStorage(tester, api);

    expect(tester.takeException(), isNull);
    expect(find.text('17.0 MB'), findsOneWidget);
    expect(find.text('31 · 4.59 MB'), findsOneWidget, reason: 'all photos');
    expect(find.text('2 · 300 KB'), findsOneWidget, reason: 'unused photos');
    expect(find.text('Zay Shae'), findsOneWidget);
    // A shop no longer in the live list still shows, by its id.
    expect(find.text('shop-gone'), findsOneWidget);
    // Rows with an empty shop_id get a label, not a blank title.
    expect(find.text('Not tied to a shop'), findsOneWidget);
    expect(find.text('Older uploads (no shop folder)'), findsOneWidget);
    expect(find.textContaining('Revisit that once'), findsOneWidget);

    await tester.tap(find.text('2 files · 300 KB'));
    await tester.pumpAndSettle();
    expect(find.text('shop-a/p-1.jpg'), findsOneWidget);
  });

  testWidgets('the app bar Reload refetches Storage too', (tester) async {
    final api = _FakeApi();
    await _openStorage(tester, api);
    expect(api.storageFetches, 1);
    await tester.tap(find.byTooltip('Reload'));
    await tester.pumpAndSettle();
    expect(api.storageFetches, 2);
  });

  testWidgets('a failed fetch offers a retry instead of a blank page', (
    tester,
  ) async {
    final api = _FakeApi()..fail = true;
    await _openStorage(tester, api);
    expect(find.byType(ErrorRetryView), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Zay Shae'), findsOneWidget);
  });
}
