import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/build_flags.dart';
import '../../core/currency_def.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import '../support/support_providers.dart';
import 'referral_providers.dart';
import 'referral_repository.dart';

/// "Refer & earn" — the retention surface. Shows the shop's own code, a running
/// earnings balance, progress toward the next free month, and a one-tap redeem.
class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  bool _busy = false;

  Future<void> _redeem() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Confirm first, showing exactly how much converts to how many months.
    final summary = ref.read(referralSummaryProvider).valueOrNull;
    // Must match the SQL function's own fallback (`coalesce(..., 10000)` in
    // migration 0014) — this said 20000, so on a device whose cached vendor
    // config never carried `price.monthly` the screen and the server
    // disagreed by 2x: a 15,000 Ks balance was refused here while the server
    // would have granted a month, and a 40,000 balance promised 2 months in
    // the dialog where the server granted 4.
    const fallbackMonthlyPriceKs = 10000;
    final rawPrice = ref.read(vendorConfigProvider).valueOrNull
            ?.priceFor('monthly') ??
        fallbackMonthlyPriceKs;
    final price = rawPrice <= 0 ? fallbackMonthlyPriceKs : rawPrice;
    final months = summary == null ? 0 : summary.balance ~/ price;
    if (months < 1) {
      messenger.showSnackBar(SnackBar(content: Text(l.referralRedeemNotEnough)));
      return;
    }
// Referral money is Myanmar kyat, always. Commissions are recorded in Ks
// server-side (`referral_commissions.base_amount`, migration 0013) and the
// licence price the balance is redeemed against is Ks too — the vendor bills
// in kyat regardless of the currency a shop SELLS in. Formatting these with
// `shopCurrencyProvider` (the POS's selling currency) rendered a 30,000 Ks
// balance as "300.00 ฿" for a THB shop: wrong by the exponent AND in a
// currency the vendor never charges. `/renew` already hardcodes Ks for the
// same reason (renew_request_page.dart).
    const currency = CurrencyDef.mmk;
    final locale = Localizations.localeOf(context).languageCode;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.referralRedeemConfirmTitle),
        content: Text(l.referralRedeemConfirmBody(
            months, Money(months * price).withCurrency(currency, locale))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.referralRedeemAction)),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final done = await ref.read(referralRepositoryProvider).redeem();
      if (done > 0) {
        messenger.showSnackBar(
            SnackBar(content: Text(l.referralRedeemDone(done))));
        // Refresh earnings + pull the extended expiry into the license state.
        ref.invalidate(referralSummaryProvider);
        await ref.read(licenseControllerProvider.notifier).refreshOnline();
      } else {
        messenger.showSnackBar(
            SnackBar(content: Text(l.referralRedeemNotEnough)));
      }
    } catch (_) {
      // NOT "not enough balance" — this catch also swallows a dropped
      // connection, an expired session, and the SQL function's own
      // "no shop context" / "no license for shop" errors. Telling an owner
      // their visibly non-zero balance is insufficient is both false and
      // unactionable.
      messenger
          .showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(String code) async {
    final l = AppLocalizations.of(context);
    final profile = await ref.read(shopProfileProvider.future);
    await SharePlus.instance.share(
      ShareParams(text: l.referralShareText(code, profile.name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Refer & earn is commerce end to end — it quotes the monthly price,
    // accrues a commission when a referred shop pays, and redeems that
    // balance for licence days. Settings already hides the only entrance in
    // a store build (see kCommerceUiEnabled); this second guard means a
    // future navigation path can't resurrect the screen behind its back.
    if (!kCommerceUiEnabled) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final summaryAsync = ref.watch(referralSummaryProvider);
    final cfg = ref.watch(vendorConfigProvider);
    final monthly = cfg.valueOrNull?.priceFor('monthly') ?? 20000;
    const currency = CurrencyDef.mmk;

    return Scaffold(
      appBar: AppBar(title: Text(l.referralTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(referralSummaryProvider);
          ref.invalidate(referredShopsProvider);
        },
        child: summaryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: [
            EmptyStateView(
              icon: Icons.card_giftcard_outlined,
              title: l.referralEmpty,
            ),
          ]),
          data: (s) => ListView(
            padding: const EdgeInsets.all(AppTheme.space4),
            children: [
              _WalletCard(
                summary: s,
                monthlyPrice: monthly,
                busy: _busy,
                onRedeem: _redeem,
                currency: currency,
              ),
              const SizedBox(height: AppTheme.space3),
              _CodeCard(
                code: s.code,
                onShare: s.code == null ? null : () => _share(s.code!),
              ),
              const SizedBox(height: AppTheme.space2),
              Text(l.referralSubtitle,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppTheme.space4),
              const _HowItWorksCard(),
              const SizedBox(height: AppTheme.space4),
              Text(l.referralActiveShops,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppTheme.space2),
              const _ReferredList(),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.summary,
    required this.monthlyPrice,
    required this.busy,
    required this.onRedeem,
    required this.currency,
  });

  final ReferralSummary summary;
  final int monthlyPrice;
  final bool busy;
  final VoidCallback onRedeem;
  final CurrencyDef currency;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    final price = monthlyPrice <= 0 ? 20000 : monthlyPrice;
    final canRedeem = summary.balance >= price;
    // Progress toward the next whole free month.
    final within = summary.balance % price;
    final progress = (within / price).clamp(0.0, 1.0).toDouble();
    final remaining = price - within;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.referralBalance,
                style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer)),
            const SizedBox(height: AppTheme.space1),
            Text(
              Money(summary.balance).withCurrency(currency, locale),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AppTheme.space2),
            // Wrap, not Row+Spacer: two unconstrained Text widgets in a Row
            // overflowed the card on the right at this locale's phrase
            // lengths (found live, in `my`) — Myanmar labels run longer than
            // their English source, so the pair needs to be free to drop to
            // a second line instead of being forced onto one.
            Wrap(
              spacing: AppTheme.space3,
              runSpacing: AppTheme.space1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.storefront,
                        size: 16, color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(width: AppTheme.space1),
                    Text('${l.referralActiveShops}: ${summary.activeReferrals}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer)),
                  ],
                ),
                Text(
                    '${l.referralEarnedTotal}: ${Money(summary.earned).withCurrency(currency, locale)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer)),
              ],
            ),
            const SizedBox(height: AppTheme.space3),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: theme.colorScheme.surface.withValues(alpha: .4),
              ),
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              canRedeem
                  ? l.referralRedeem
                  : l.referralNextGoal(Money(remaining).withCurrency(currency, locale)),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: AppTheme.space3),
            FilledButton.icon(
              onPressed: (busy || !canRedeem) ? null : onRedeem,
              icon: busy ? const ButtonSpinner() : const Icon(Icons.redeem),
              label: Text(l.referralRedeem),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.onShare});

  final String? code;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.referralMyCode, style: theme.textTheme.labelLarge),
            const SizedBox(height: AppTheme.space1),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    code ?? '—',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                if (code != null)
                  IconButton(
                    tooltip: l.referralCopied,
                    icon: const Icon(Icons.copy),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code!));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.referralCopied)));
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space2),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: onShare,
                icon: const Icon(Icons.share),
                label: Text(l.referralShare),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short numbered "how it works" explainer so the feature is self-teaching.
class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final steps = [
      l.referralStep1,
      l.referralStep2,
      l.referralStep3,
      l.referralStep4,
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: AppTheme.space2),
                Text(l.referralHowTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: AppTheme.space3),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: EdgeInsets.only(
                    bottom: i == steps.length - 1 ? 0 : AppTheme.space2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconAvatar(text: '${i + 1}', size: 24),
                    const SizedBox(width: AppTheme.space2),
                    Expanded(
                        child: Text(steps[i],
                            style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReferredList extends ConsumerWidget {
  const _ReferredList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final shopsAsync = ref.watch(referredShopsProvider);
    return shopsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppTheme.space3),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => EmptyStateView(
        icon: Icons.storefront_outlined,
        title: l.referralEmpty,
      ),
      data: (shops) {
        if (shops.isEmpty) {
          return EmptyStateView(
            icon: Icons.storefront_outlined,
            title: l.referralEmpty,
          );
        }
        final df = DateFormat.yMMMd();
        return Column(
          children: [
            for (final s in shops)
              ListTile(
                dense: true,
                leading: IconAvatar(
                  icon: s.active ? Icons.check : Icons.pause,
                  tone: s.active ? StatusTone.positive : StatusTone.neutral,
                  size: 36,
                ),
                title: Text('#${_mask(s.shopId)}'),
                subtitle: s.createdAt != null
                    ? Text(df.format(s.createdAt!.toLocal()))
                    : null,
              ),
          ],
        );
      },
    );
  }

  // Shops are identified by opaque ids; show a short, non-identifying tail.
  String _mask(String shopId) {
    final tail = shopId.length <= 4 ? shopId : shopId.substring(shopId.length - 4);
    return tail.toUpperCase();
  }
}
