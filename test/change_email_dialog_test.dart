import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/l10n/app_localizations.dart';
import 'package:mm_pos/features/account/account_repository.dart';
import 'package:mm_pos/features/account/change_email_dialog.dart';

Widget host(
  Locale locale,
  Future<AccountActionResult> Function(String) submit,
) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showChangeEmailDialog(context, submit: submit),
        child: const Text('Open'),
      ),
    ),
  ),
);
void main() {
  for (final locale in [const Locale('en'), const Locale('my')]) {
    testWidgets('email failure stays actionable in ${locale.languageCode}', (
      tester,
    ) async {
      final l = await AppLocalizations.delegate.load(locale);
      await tester.pumpWidget(
        host(
          locale,
          (_) async => const AccountActionResult.failure('email_taken'),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'new@example.com');
      await tester.tap(find.widgetWithText(FilledButton, l.accountChangeEmail));
      await tester.pumpAndSettle();
      expect(find.text(l.accountEmailTaken), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('email request cannot be submitted twice while pending', (
    tester,
  ) async {
    final pending = Completer<AccountActionResult>();
    var calls = 0;
    await tester.pumpWidget(
      host(const Locale('en'), (_) {
        calls++;
        return pending.future;
      }),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Change email'));
    await tester.pump();
    expect(calls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.complete(const AccountActionResult.success('same-owner'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
