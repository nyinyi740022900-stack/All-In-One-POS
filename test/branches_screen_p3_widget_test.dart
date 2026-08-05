import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/account/branch_providers.dart';
import 'package:mm_pos/features/account/branch_repository.dart';
import 'package:mm_pos/features/account/branches_screen.dart';
import 'package:mm_pos/features/license/license_providers.dart';
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
  Future<void> pumpBranches(
    WidgetTester tester, {
    required bool online,
    required int pendingOutbox,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isPremiumProvider.overrideWith((ref) => true),
          isEffectiveOwnerProvider.overrideWith((ref) => true),
          licenseControllerProvider.overrideWith(
            (ref) => _FakeLicenseController(ref),
          ),
          branchesProvider.overrideWith(
            (ref) async => const [
              Branch(shopId: 'shop-main', label: 'Main', isCurrent: true),
              Branch(shopId: 'shop-branch', label: 'Branch', isCurrent: false),
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
}
