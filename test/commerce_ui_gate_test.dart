import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/build_flags.dart';
import 'package:mm_pos/features/license/premium_gate.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// App Store guideline 3.1.1 bans buttons/links steering to a purchasing
/// mechanism outside in-app purchase, and that ban is lifted only on the US
/// storefront — never in Myanmar. The store build therefore ships with
/// [kCommerceUiEnabled] off and leans on 3.1.3(b) Multiplatform Services
/// instead. These tests pin the two things that would quietly undo that: the
/// default flipping to true, and a commerce label leaking into the default
/// build.
///
/// Tests run with no `--dart-define`, so they see exactly the store build's
/// view of the flag.
void main() {
  test('commerce UI is off unless a build explicitly opts in', () {
    expect(
      kCommerceUiEnabled,
      isFalse,
      reason: 'COMMERCE_UI must default to false — an App Store build that '
          'forgets the define has to stay compliant, not become a violation.',
    );
  });

  test('the Premium CTA says "Manage license", never "Upgrade"', () async {
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(upgradeCtaLabel(l), l.premiumManageLicenseCta);
    expect(upgradeCtaLabel(l), isNot(l.premiumUpgradeCta));
  });

  // A stray `l.licensePayOnline` re-added somewhere ungated is exactly how
  // this protection dies quietly: analyzer-clean, tests green, and a
  // purchase button back on screen in the store build. Rendering the real
  // License screen here would need the whole Drift/Supabase stack, so scan
  // the source instead — every commerce-only string must live in a file
  // that also consults [kCommerceUiEnabled].
  test('every commerce-only string sits in a flag-guarded file', () {
    const commerceGetters = <String>[
      'licensePayOnline',
      'licensePayOnlineHint',
      'licenseBuyOrRenewTitle',
      'licenseBuyOrRenewIntro',
      'licenseContactViber',
      'licenseContactViberHint',
      'licenseContactViberHintOnline',
      'licenseAfterPaymentTitle',
      'premiumUpgradeCta',
      'licenseExpiringSoon',
    ];

    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.startsWith('lib/l10n/')) continue; // generated + ARB
      final src = entity.readAsStringSync();
      if (src.contains('kCommerceUiEnabled')) continue;
      for (final getter in commerceGetters) {
        // The trailing \b is what keeps `l.licenseExpiringSoon` from also
        // matching its own neutral variant, `l.licenseExpiringSoonNeutral`
        // — there is no word boundary between "Soon" and "Neutral".
        if (RegExp('\\bl\\.$getter\\b').hasMatch(src)) {
          offenders.add('${entity.path} → l.$getter');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These files show purchase/pricing UI without consulting '
          'kCommerceUiEnabled, so an App Store build would ship it '
          '(guideline 3.1.1):\n  ${offenders.join('\n  ')}',
    );
  });
}
