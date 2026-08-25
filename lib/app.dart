import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/locale_controller.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_widgets.dart';
import 'data/sync/sync_providers.dart';
import 'features/accounts/payment_account_providers.dart';
import 'features/expenses/recurring_expense_providers.dart';
import 'features/license/license_expiry_watcher.dart';
import 'features/license/license_providers.dart';
import 'features/account/password_recovery_watcher.dart';
import 'features/account/reset_password_screen.dart';
import 'features/onboarding/daily_gate.dart';
import 'features/onboarding/full_screen_gate.dart';
import 'features/onboarding/onboarding_state.dart';
import 'features/onboarding/operating_mode_providers.dart';
import 'features/referral/referral_watcher.dart';
import 'features/storefront/storefront_order_watcher.dart';
import 'l10n/app_localizations.dart';

/// Shown once per install, before the tabbed shell. Onboarding itself lives
/// at the router route `/onboarding` (see `appRouterProvider`); this screen
/// only holds launch while the completion flag is being read.
final _onboardingForcedDoneProvider = onboardingForcedDoneProvider;

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
    // Remind the owner before Premium lapses. Nothing can charge a shop
    // automatically (MMQR is customer-push), so warning in time is the only
    // part of renewal that can be automated at all.
    ref.watch(licenseExpiryWatcherProvider);
    // Auto-generate any due recurring-expense templates once per launch.
    ref.watch(recurringExpenseGeneratorProvider);
    // Seed the default payment accounts once per shop.
    ref.watch(paymentAccountSeederProvider);
    // Listen for password-recovery deep links for the whole app lifetime.
    ref.watch(passwordRecoveryWatcherProvider);

    // Loading reads as "done" so the (effectively instant) first Drift read
    // never flashes onboarding for a frame on every ordinary launch.
    final forcedDone = ref.watch(_onboardingForcedDoneProvider);
    final showPasswordRecovery = ref.watch(passwordRecoveryPendingProvider);
    final dailyGateAsync = ref.watch(dailyGateNeededProvider);
    // Onboarding is a router route now; while it's up, neither the hold
    // screen nor the daily gate may paint over it.
    final onboardingNeeded = !forcedDone &&
        ref.watch(onboardingCompleteProvider).valueOrNull == false;
    // Every install must not flash the Sell shell while we resolve whether
    // today's entry gate is still needed.
    final holdForDailyCheck = !onboardingNeeded && !dailyGateAsync.hasValue;
    final showDailyGate =
        !onboardingNeeded && (dailyGateAsync.valueOrNull == true);

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
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        // PIN / confirm dialogs need a Navigator ancestor — without one,
        // Continue as Owner throws in release and looks like a dead tap.
        Widget gated(Widget page) =>
            FullScreenGate(page: page, underneath: child);

        if (showPasswordRecovery) {
          return gated(const ResetPasswordScreen());
        }
        // Onboarding moved OUT of this builder into a real router route
        // (`/onboarding`, see appRouterProvider): the overlay's close path
        // — provider write → this builder swapping the subtree — silently
        // never painted on one owner device even though every step ran,
        // leaving Get started looking dead. A route leaves via ordinary
        // navigation. The loading-hold stays here so launch never flashes
        // the shell before the (instant) first DB read resolves.
        if (!forcedDone &&
            ref.watch(onboardingCompleteProvider).isLoading &&
            !ref.watch(onboardingCompleteProvider).hasValue &&
            !ref.watch(onboardingCompleteProvider).hasError) {
          final l = AppLocalizations.of(context);
          return Scaffold(
            body: AppLoadingView(message: l.dailyGateCheckingShop),
          );
        }
        if (holdForDailyCheck) {
          final l = AppLocalizations.of(context);
          return Scaffold(
            body: AppLoadingView(message: l.dailyGateCheckingShop),
          );
        }
        if (showDailyGate) {
          return gated(
            DailyGate(
              onDone: () => ref.invalidate(dailyGateNeededProvider),
            ),
          );
        }
        return child!;
      },
    );
  }
}
