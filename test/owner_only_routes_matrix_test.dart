import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/account/branch_providers.dart';
import 'package:mm_pos/features/account/branches_screen.dart';
import 'package:mm_pos/features/account/staff_accounts_screen.dart';
import 'package:mm_pos/features/analytics/analytics_screen.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_screen.dart';
import 'package:mm_pos/features/storefront/storefront_screen.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

class _FakeLicenseController extends LicenseController {
  _FakeLicenseController(super.ref) {
    state = const LicenseState(loading: false);
  }

  @override
  Future<void> load() async {}
}

void main() {
  Future<void> pumpStaffLockedRoute(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
          activeStaffIdProvider.overrideWith((ref) => Stream.value(null)),
          branchSwitchRecoveryProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
          isPremiumProvider.overrideWithValue(true),
          licenseControllerProvider
              .overrideWith((ref) => _FakeLicenseController(ref)),
          // Avoid AsyncLoading→owner default briefly opening the real body
          // (same race documented in license_screen_staff_lock_test.dart) —
          // without this, LicenseScreen's real body flashes open for one
          // frame and reaches _StatusCard, which needs AppColors registered
          // on the theme; this test's plain MaterialApp has no theme set.
          isEffectiveOwnerProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('staff is blocked from owner-only routes matrix', (tester) async {
    await pumpStaffLockedRoute(tester, const LicenseScreen());
    expect(find.byIcon(Icons.lock_outline), findsWidgets);

    await pumpStaffLockedRoute(tester, const StorefrontScreen());
    expect(find.byIcon(Icons.lock_outline), findsWidgets);

    await pumpStaffLockedRoute(tester, const AnalyticsScreen());
    expect(find.byIcon(Icons.lock_outline), findsWidgets);

    await pumpStaffLockedRoute(tester, const BranchesScreen());
    expect(find.byIcon(Icons.lock_outline), findsWidgets);

    await pumpStaffLockedRoute(tester, const StaffAccountsScreen());
    expect(find.byIcon(Icons.lock_outline), findsWidgets);
  });
}
