import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/integrity/app_integrity.dart';
import 'package:mm_pos/core/integrity/tampered_app.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

void main() {
  const ours = 'A80738070C8D447FEB1F6B1CF1EC3CDA897F5914EC623F99506BE8D79F43AFE4';
  const theirs = '00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF';
  final allowed = {ours};

  group('evaluate', () {
    test('our signature is genuine, in any hex spelling', () {
      final colonLower = [
        for (var i = 0; i < ours.length; i += 2) ours.substring(i, i + 2),
      ].join(':').toLowerCase();
      for (final s in [ours, colonLower]) {
        expect(
          AppIntegrity.evaluate(
            signers: [s],
            debuggable: false,
            allowed: allowed,
          ),
          IntegrityVerdict.genuine,
        );
      }
    });

    test('a re-signed APK is tampered', () {
      expect(
        AppIntegrity.evaluate(
          signers: [theirs],
          debuggable: false,
          allowed: allowed,
        ),
        IntegrityVerdict.tampered,
      );
    });

    test('a release build made debuggable is tampered, even with our key', () {
      expect(
        AppIntegrity.evaluate(signers: [ours], debuggable: true, allowed: allowed),
        IntegrityVerdict.tampered,
      );
    });

    test('unreadable facts never block — a guess must not lock a till', () {
      for (final signers in [null, <String>[]]) {
        expect(
          AppIntegrity.evaluate(
            signers: signers,
            debuggable: false,
            allowed: allowed,
          ),
          IntegrityVerdict.unknown,
        );
      }
    });
  });

  test('the upload key and the Play app signing key are both allowed', () {
    // Without the Play key every Play install would hit the block screen.
    expect(AppIntegrity.allowedSigners, contains(ours));
    expect(
      AppIntegrity.allowedSigners,
      contains(
        '5AF5B5F26006DB3D0237126B3BD6FDB9FADC81240C9D33E90447FCFB0B5C9B05',
      ),
    );
    expect(AppIntegrity.playKeyKnown, isTrue);
    for (final s in AppIntegrity.allowedSigners) {
      expect(s, matches(RegExp(r'^[0-9A-F]{64}$')), reason: s);
    }
  });

  test('a test (debug) run is never blocked', () async {
    expect(await AppIntegrity.check(), IntegrityVerdict.genuine);
  });

  testWidgets('tampered screen explains and links to the official app', (
    tester,
  ) async {
    final l = lookupAppLocalizations(const Locale('en'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const TamperedScreen(),
      ),
    );
    expect(find.text(l.tamperedTitle), findsOneWidget);
    expect(find.text(l.tamperedNextStep), findsOneWidget);
    expect(find.text(l.tamperedGetApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
