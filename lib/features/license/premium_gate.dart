import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/build_flags.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import 'license_providers.dart';
import 'license_screen.dart';

/// Wraps a whole screen's body: shown as-is on the Premium plan, otherwise
/// replaced with a locked paywall (feature name + short explanation + a CTA
/// into the License screen). Mirrors `OwnerOnlyGate`'s shape — compose the
/// two when a screen needs both checks (see e.g. `AnalyticsScreen`).
///
/// The CTA reads "Upgrade" only where selling is allowed; a store build
/// (see [kCommerceUiEnabled]) says "Manage license" instead. Same
/// destination either way — but "Upgrade" is a call to action to buy, and
/// App Store guideline 3.1.1 judges the wording, not the destination.
class PremiumGate extends ConsumerWidget {
  const PremiumGate({
    super.key,
    required this.child,
    required this.featureName,
    this.benefits,
  });
  final Widget child;
  final String featureName;

  /// Concrete, outcome-focused bullets shown on the paywall instead of (or
  /// alongside) the generic explanation — "best-sellers at a glance" reads
  /// as a reason to upgrade; "this feature needs Premium" alone doesn't.
  /// Optional and additive: omitting it keeps the exact previous behavior.
  final List<String>? benefits;

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
      benefits: benefits,
    );
  }
}

class _PremiumPaywall extends StatelessWidget {
  const _PremiumPaywall({
    required this.featureName,
    required this.hasAccount,
    this.benefits,
  });
  final String featureName;
  final bool hasAccount;
  final List<String>? benefits;

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
            if (benefits != null && benefits!.isNotEmpty) ...[
              const SizedBox(height: AppTheme.space3),
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final b in benefits!)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle,
                                size: 16,
                                color: AppColors.of(context).success),
                            const SizedBox(width: AppTheme.space2),
                            Flexible(child: Text(b)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppTheme.space4),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LicenseScreen(),
              )),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: Text(upgradeCtaLabel(l)),
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
    BuildContext context, String featureName, {String? benefit}) {
  final l = AppLocalizations.of(context);
  final hasAccount = ProviderScope.containerOf(
    context,
  ).read(hasRealAccountSessionProvider);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.premiumFeatureTitle(featureName)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hasAccount ? l.premiumFeatureBodyOnline : l.premiumFeatureBody),
          if (benefit != null) ...[
            const SizedBox(height: AppTheme.space2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle,
                    size: 16, color: AppColors.of(ctx).success),
                const SizedBox(width: AppTheme.space2),
                Flexible(child: Text(benefit)),
              ],
            ),
          ],
        ],
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
          child: Text(upgradeCtaLabel(l)),
        ),
      ],
    ),
  );
}

/// Label for every "this is Premium → go to the License screen" button.
/// Shared by [PremiumGate], [showPremiumRequiredDialog] and Settings'
/// `_LockedTile`s so a store build can never end up with one stray
/// "Upgrade" left behind.
String upgradeCtaLabel(AppLocalizations l) =>
    kCommerceUiEnabled ? l.premiumUpgradeCta : l.premiumManageLicenseCta;
