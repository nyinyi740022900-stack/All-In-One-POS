import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import 'license_providers.dart';
import 'license_screen.dart';

/// Wraps a whole screen's body: shown as-is on the Premium plan, otherwise
/// replaced with a locked paywall (feature name + short explanation +
/// "Upgrade" CTA). Mirrors `OwnerOnlyGate`'s shape — compose the two when a
/// screen needs both checks (see e.g. `AnalyticsScreen`).
class PremiumGate extends ConsumerWidget {
  const PremiumGate({super.key, required this.child, required this.featureName});
  final Widget child;
  final String featureName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licState = ref.watch(licenseControllerProvider);
    // Before `LicenseController.load()` resolves, `license` is null and
    // `isPremium` would read as false — without this check every gated
    // screen would flash the paywall for a frame on cold start, even for a
    // genuinely Premium shop, until the cached license finishes loading.
    if (licState.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (licState.isPremium) return child;
    return _PremiumPaywall(
      featureName: featureName,
      hasAccount: ref.watch(hasRealAccountSessionProvider),
    );
  }
}

class _PremiumPaywall extends StatelessWidget {
  const _PremiumPaywall({
    required this.featureName,
    required this.hasAccount,
  });
  final String featureName;
  final bool hasAccount;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_outlined,
                size: 56, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: AppTheme.space3),
            Text(l.premiumFeatureTitle(featureName),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: AppTheme.space2),
            Text(
              hasAccount ? l.premiumFeatureBodyOnline : l.premiumFeatureBody,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.space4),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LicenseScreen(),
              )),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: Text(l.premiumUpgradeCta),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact paywall for a single gated *action* inside an otherwise-free
/// screen (e.g. Inventory's CSV export button) rather than a whole screen
/// body — same copy/CTA as [PremiumGate], as a dialog instead.
Future<void> showPremiumRequiredDialog(
    BuildContext context, String featureName) {
  final l = AppLocalizations.of(context);
  final hasAccount = ProviderScope.containerOf(
    context,
  ).read(hasRealAccountSessionProvider);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.premiumFeatureTitle(featureName)),
      content: Text(
        hasAccount ? l.premiumFeatureBodyOnline : l.premiumFeatureBody,
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const LicenseScreen(),
            ));
          },
          child: Text(l.premiumUpgradeCta),
        ),
      ],
    ),
  );
}
