import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/account/branch_providers.dart';
import 'package:mm_pos/features/account/branch_repository.dart';
import 'package:mm_pos/features/account/branches_screen.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_status.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

class _FakeLicenseController extends LicenseController {
  _FakeLicenseController(
    super.ref, {
    CachedLicense? license,
  }) {
    state = LicenseState(loading: false, license: license);
  }

  @override
  Future<void> load() async {}
}

void main() {
  Future<void> pumpBranches(
    WidgetTester tester, {
    required bool online,
    required int pendingOutbox,
    bool markCurrentInBranchList = true,
  }) async {
    final now = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isPremiumProvider.overrideWith((ref) => true),
          isEffectiveOwnerProvider.overrideWith((ref) => true),
          licenseControllerProvider.overrideWith(
            (ref) => _FakeLicenseController(
              ref,
              license: CachedLicense(
                key: 'K',
                shopId: 'shop-main',
                plan: LicensePlan.trial,
                expiresAt: now.add(const Duration(days: 30)),
                activatedAt: now,
                lastVerifiedAt: now,
                deviceId: 'device-1',
              ),
            ),
          ),
          branchesProvider.overrideWith(
            (ref) async => [
              Branch(
                shopId: 'shop-main',
                label: 'Main',
                isCurrent: markCurrentInBranchList,
              ),
              Branch(
                shopId: 'shop-branch',
                label: 'Branch',
                isCurrent: false,
              ),
            ],
          ),
          branchSwitchRecoveryProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
          pendingOutboxCountProvider.overrideWith(
            (ref) => Stream.value(pendingOutbox),
          ),
          branchConnectivityProvider.overrideWith(
            (ref) => Stream.value(online),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const BranchesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders pinned current branch and explicit action sections', (
    tester,
  ) async {
    await pumpBranches(tester, online: true, pendingOutbox: 0);

    expect(find.text('Pinned current branch'), findsOneWidget);
    expect(find.text('Current branch'), findsOneWidget);
    expect(find.text('Other branches'), findsOneWidget);

    expect(find.widgetWithText(OutlinedButton, 'Switch'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Unlink'), findsOneWidget);
  });

  testWidgets('shows safe-to-switch health chip when online and clean', (
    tester,
  ) async {
    await pumpBranches(tester, online: true, pendingOutbox: 0);
    expect(find.text('Safe to switch'), findsWidgets);
    expect(find.text('Sync needed'), findsNothing);
  });

  testWidgets('shows sync-needed health chip when offline or pending', (
    tester,
  ) async {
    await pumpBranches(tester, online: false, pendingOutbox: 2);
    expect(find.text('Sync needed'), findsWidgets);
  });

  testWidgets('uses active license shop as current branch fallback', (tester) async {
    await pumpBranches(
      tester,
      online: true,
      pendingOutbox: 0,
      markCurrentInBranchList: false,
    );
    expect(find.text('Pinned current branch'), findsOneWidget);
    expect(find.text('Main'), findsWidgets);
  });

  testWidgets('shows network retry state when branch list errors', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isPremiumProvider.overrideWith((ref) => true),
          isEffectiveOwnerProvider.overrideWith((ref) => true),
          licenseControllerProvider.overrideWith(
            (ref) => _FakeLicenseController(
              ref,
              license: CachedLicense(
                key: 'K',
                shopId: 'shop-main',
                plan: LicensePlan.trial,
                expiresAt: now.add(const Duration(days: 30)),
                activatedAt: now,
                lastVerifiedAt: now,
                deviceId: 'device-1',
              ),
            ),
          ),
          branchesProvider.overrideWith(
            (ref) async => throw const BranchListException('network_error'),
          ),
          branchSwitchRecoveryProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
          pendingOutboxCountProvider.overrideWith((ref) => Stream.value(0)),
          branchConnectivityProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const BranchesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(BranchesScreen)));
    expect(find.text(l.branchesNetworkRetry), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, l.syncNow), findsOneWidget);
  });
}
