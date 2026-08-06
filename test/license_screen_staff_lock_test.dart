import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/account/account_providers.dart';
import 'package:mm_pos/features/license/license_screen.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

void main() {
  testWidgets('staff cannot access License screen actions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendAccountRoleProvider.overrideWithValue('staff'),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LicenseScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.link_off), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
  });
}
