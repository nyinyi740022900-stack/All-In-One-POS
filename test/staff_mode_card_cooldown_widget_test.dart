import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/features/staff/staff_ui.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'staff mode card disables owner switch and shows cooldown countdown',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
            ownerPinCooldownSecondsProvider.overrideWith(
              (ref) => Stream.value(25),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: StaffModeCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchOwner = find.widgetWithText(ListTile, 'Switch to Owner');
      expect(switchOwner, findsOneWidget);
      expect(find.textContaining('Try again in 25s'), findsOneWidget);
      final tile = tester.widget<ListTile>(switchOwner);
      expect(tile.enabled, isFalse);
      expect(tile.onTap, isNull);
    },
  );
}
