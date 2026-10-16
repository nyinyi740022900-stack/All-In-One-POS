import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/data/local/db_encryption.dart';
import 'package:mm_pos/features/backup/db_locked_app.dart';
import 'package:mm_pos/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;

void main() {
  final l = lookupAppLocalizations(const Locale('en'));

  Future<void> pump(
    WidgetTester tester, {
    required DbLockReason reason,
    required Future<void> Function() onUnlocked,
    String documentsDir = '/nonexistent',
    String? support,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: DbLockedScreen(
          error: DbKeyUnavailableException(reason),
          documentsDir: documentsDir,
          onUnlocked: onUnlocked,
          loadSupportNumber: () async => support,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('explains the lock per reason; Retry that fails again says so '
      'and stays on the screen', (tester) async {
    var tries = 0;
    await pump(
      tester,
      reason: DbLockReason.keyUnreadable,
      onUnlocked: () async {
        tries++;
        throw DbKeyUnavailableException(DbLockReason.keyUnreadable);
      },
    );
    expect(find.text(l.dbLockedTitle), findsOneWidget);
    expect(find.text(l.dbLockedUnreadableHint), findsOneWidget);
    expect(find.text(l.dbLockedSupport), findsNothing, reason: 'no number');

    await tester.tap(find.text(l.dbLockedRetry));
    await tester.pumpAndSettle();
    expect(tries, 1);
    expect(find.text(l.dbLockedStillLocked), findsOneWidget);
    expect(find.text(l.dbLockedTitle), findsOneWidget);
  });

  testWidgets('missing key shows its own hint and the support button when a '
      'number is known', (tester) async {
    await pump(
      tester,
      reason: DbLockReason.keyMissing,
      onUnlocked: () async {},
      support: '09123456789',
    );
    expect(find.text(l.dbLockedMissingHint), findsOneWidget);
    expect(find.text(l.dbLockedSupport), findsOneWidget);
  });

  testWidgets('start with an empty shop asks first; cancelling moves nothing',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('mm_pos_locked_ui_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, 'mm_pos_shop-1.sqlite')).writeAsBytesSync([1, 2, 3]);
    var started = 0;
    await pump(
      tester,
      reason: DbLockReason.keyMissing,
      documentsDir: dir.path,
      onUnlocked: () async => started++,
    );

    await tester.tap(find.text(l.dbLockedStartEmpty));
    await tester.pumpAndSettle();
    expect(find.text(l.dbLockedStartEmptyBody), findsOneWidget);
    await tester.tap(find.text(l.commonCancel));
    await tester.pumpAndSettle();
    expect(started, 0);
    expect(File(p.join(dir.path, 'mm_pos_shop-1.sqlite')).existsSync(), isTrue);
  });
}
