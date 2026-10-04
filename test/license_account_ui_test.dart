import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/account/account_providers.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_screen.dart';
import 'package:mm_pos/features/license/license_status.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/features/support/support_providers.dart';
import 'package:mm_pos/features/support/vendor_config.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

class _FreeController extends LicenseController {
  _FreeController(
    super.ref, {
    LicensePlan plan = LicensePlan.free,
    int daysLeft = -30,
  }) {
    final lic = CachedLicense(
      key: 'FREE',
      shopId: 'free-local',
      plan: plan,
      expiresAt: DateTime.now().add(Duration(days: daysLeft)),
      activatedAt: DateTime(2026),
      lastVerifiedAt: DateTime(2026),
      deviceId: 'device',
    );
    state = LicenseState(
      loading: false,
      license: lic,
      status: computeLicenseStatus(
        expiresAt: lic.expiresAt,
        plan: lic.plan,
        now: DateTime.now(),
      ),
    );
  }
}

void main() {
  for (final locale in ['en', 'my']) {
    for (final entry in <String, (LicensePlan, int)>{
      'Free': (LicensePlan.free, -30),
      'active': (LicensePlan.monthly, 30),
      'grace': (LicensePlan.monthly, -1),
      'expired': (LicensePlan.monthly, -30),
    }.entries) {
      testWidgets(
        'store Premium screen has no payment steering ($locale, ${entry.key})',
        (tester) async {
          final l = await AppLocalizations.delegate.load(Locale(locale));
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                licenseControllerProvider.overrideWith(
                  (ref) => _FreeController(
                    ref,
                    plan: entry.value.$1,
                    daysLeft: entry.value.$2,
                  ),
                ),
                isEffectiveOwnerProvider.overrideWithValue(true),
                hasRealAccountSessionProvider.overrideWithValue(true),
                vendorConfigProvider.overrideWith(
                  (ref) async =>
                      const VendorConfig(supportViber: '09999999999'),
                ),
                shopDevicesProvider.overrideWith((ref) async => []),
                deviceIdProvider.overrideWith((ref) async => 'device'),
              ],
              child: MaterialApp(
                theme: AppTheme.light(localeCode: locale),
                locale: Locale(locale),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const LicenseScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(l.licensePayOnline), findsNothing);
          expect(find.text(l.licenseContactViber), findsNothing);
          expect(find.text(l.licenseFreeTrial), findsNothing);
          expect(find.textContaining('09999999999'), findsNothing);
          expect(find.byIcon(Icons.open_in_new), findsNothing);
          expect(
            find.text(
              locale == 'en'
                  ? 'Sign in to your shop account to access its available Premium features. Check again to update your account status. Free features remain available.'
                  : 'သင့်ဆိုင် account တွင် အသုံးပြုခွင့်ရှိသော Premium လုပ်ဆောင်ချက်များကို သုံးရန် ဝင်ရောက်ပါ။ Account အခြေအနေကို အပ်ဒိတ်လုပ်ရန် ပြန်စစ်နိုင်ပါသည်။ Free လုပ်ဆောင်ချက်များကို ဆက်သုံးနိုင်ပါသည်။',
            ),
            findsOneWidget,
          );
          expect(find.text(l.licenseCheckRenewal), findsOneWidget);
        },
      );
    }
  }
  testWidgets(
    'Free upgrade requires account and never exposes key entry or scanner',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            licenseControllerProvider.overrideWith(
              (ref) => _FreeController(ref),
            ),
            isEffectiveOwnerProvider.overrideWithValue(true),
            hasRealAccountSessionProvider.overrideWithValue(false),
            vendorConfigProvider.overrideWith(
              (ref) async => VendorConfig.empty,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(localeCode: 'en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LicenseScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
      expect(find.text('Sign in to use Premium'), findsOneWidget);
    },
  );
}
