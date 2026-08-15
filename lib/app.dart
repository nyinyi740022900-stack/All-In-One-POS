import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/locale_controller.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'data/sync/sync_providers.dart';
import 'features/accounts/payment_account_providers.dart';
import 'features/expenses/recurring_expense_providers.dart';
import 'features/license/license_providers.dart';
import 'features/account/password_recovery_watcher.dart';
import 'features/account/reset_password_screen.dart';
import 'features/onboarding/daily_gate.dart';
import 'features/onboarding/mode_migrate_flow.dart';
import 'features/onboarding/onboarding_flow.dart';
import 'features/onboarding/operating_mode_providers.dart';
import 'features/printing/printing_providers.dart';
import 'features/referral/referral_watcher.dart';
import 'features/storefront/storefront_order_watcher.dart';
import 'l10n/app_localizations.dart';

/// Whether the one-time first-run onboarding has been completed.
final _onboardingDoneProvider = FutureProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).onboardingComplete();
});

class MmPosApp extends ConsumerWidget {
  const MmPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeCode = ref.watch(localeControllerProvider);
    // Keep these controllers alive for the whole app lifetime: the license
    // controller binds the active shop and gates selling; the sync controller
    // starts connectivity-driven syncing at launch.
    ref.watch(licenseControllerProvider);
    ref.watch(syncControllerProvider);
    // Poll for new referral commissions and fire the "earned" notification.
    ref.watch(referralWatcherProvider);
    // Alert when storefront orders land via sync.
    ref.watch(storefrontOrderWatcherProvider);
    // Auto-generate any due recurring-expense templates once per launch.
    ref.watch(recurringExpenseGeneratorProvider);
    // Seed the default payment accounts once per shop.
    ref.watch(paymentAccountSeederProvider);
    // Listen for password-recovery deep links for the whole app lifetime.
    ref.watch(passwordRecoveryWatcherProvider);

    // Shown once per install, before the tabbed shell. Loading reads as
    // "done" so the (effectively instant) first Drift read never flashes
    // onboarding for a frame on every ordinary launch.
    final showOnboarding =
        ref.watch(_onboardingDoneProvider).valueOrNull == false;
    final showPasswordRecovery = ref.watch(passwordRecoveryPendingProvider);
    final modeConfirmed =
        ref.watch(operatingModeConfirmedProvider).valueOrNull == true;
    final showModeMigrate = !showOnboarding &&
        ref.watch(operatingModeConfirmedProvider).hasValue &&
        !modeConfirmed;
    final dailyGateAsync = ref.watch(dailyGateNeededProvider);
    // Every install must not flash the Sell shell while we resolve whether
    // today's entry gate is still needed.
    final holdForDailyCheck = !showOnboarding &&
        !showModeMigrate &&
        !dailyGateAsync.hasValue;
    final showDailyGate = !showOnboarding &&
        !showModeMigrate &&
        (dailyGateAsync.valueOrNull == true);

    return MaterialApp.router(
      onGenerateTitle: (ctx) => AppLocalizations.of(ctx).appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(localeCode: localeCode),
      darkTheme: AppTheme.dark(localeCode: localeCode),
      locale: Locale(localeCode),
      // Force the chosen locale — never fall back to the device/system locale.
      localeResolutionCallback: (_, _) => Locale(localeCode),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: appRouter,
      builder: (context, child) {
        if (showPasswordRecovery) {
          return const ResetPasswordScreen();
        }
        if (showOnboarding) {
          return OnboardingFlow(
              onDone: () => ref.invalidate(_onboardingDoneProvider));
        }
        if (showModeMigrate) {
          return ModeMigrateFlow(
            onDone: () {
              ref.invalidate(operatingModeConfirmedProvider);
              ref.invalidate(operatingModeProvider);
              ref.invalidate(dailyGateNeededProvider);
            },
          );
        }
        if (holdForDailyCheck) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (showDailyGate) {
          return DailyGate(
            onDone: () => ref.invalidate(dailyGateNeededProvider),
          );
        }
        return child!;
      },
    );
  }
}
