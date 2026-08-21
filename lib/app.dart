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
import 'features/license/license_providers.dart';
import 'features/account/password_recovery_watcher.dart';
import 'features/account/reset_password_screen.dart';
import 'features/onboarding/daily_gate.dart';
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

/// Set when Get started is tapped so the gate can close even if the Drift
/// write of `onboarding.done` is stalled (device-DB lock from Free-plan
/// setup). Without this, the button stays grey forever on that page.
final _onboardingForcedDoneProvider = StateProvider<bool>((ref) => false);

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
    final forcedDone = ref.watch(_onboardingForcedDoneProvider);
    final showOnboarding =
        !forcedDone &&
        ref.watch(_onboardingDoneProvider).valueOrNull == false;
    final showPasswordRecovery = ref.watch(passwordRecoveryPendingProvider);
    final dailyGateAsync = ref.watch(dailyGateNeededProvider);
    // Every install must not flash the Sell shell while we resolve whether
    // today's entry gate is still needed.
    final holdForDailyCheck = !showOnboarding && !dailyGateAsync.hasValue;
    final showDailyGate =
        !showOnboarding && (dailyGateAsync.valueOrNull == true);

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
        // These gates *replace* [child] (the go_router Navigator). PIN /
        // confirm dialogs need a Navigator ancestor — without one,
        // Continue as Owner throws in release and looks like a dead tap.
        // SizedBox.expand is required: a bare Navigator in [builder] can
        // paint full-screen while its hit-test box stays empty, so Get
        // started / Continue look enabled but ignore taps.
        Widget gated(Widget page) {
          return SizedBox.expand(
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => page,
                fullscreenDialog: true,
              ),
            ),
          );
        }

        if (showPasswordRecovery) {
          return gated(const ResetPasswordScreen());
        }
        if (showOnboarding) {
          return gated(
            OnboardingFlow(
              onDone: () {
                ref.read(_onboardingForcedDoneProvider.notifier).state =
                    true;
                ref.invalidate(_onboardingDoneProvider);
              },
            ),
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
