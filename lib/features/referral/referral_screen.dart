import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
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
    final rawPrice =
        ref.read(vendorConfigProvider).valueOrNull?.priceFor('monthly') ?? 10000;
    final price = rawPrice <= 0 ? 10000 : rawPrice;
    final months = summary == null ? 0 : summary.balance ~/ price;
    if (months < 1) {
      messenger.showSnackBar(SnackBar(content: Text(l.referralRedeemNotEnough)));
      return;
    }
    final cur = l.currencySymbol;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.referralRedeemConfirmTitle),
        content: Text(l.referralRedeemConfirmBody(
            months, Money(months * price).withSymbol(cur))),
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
      messenger.showSnackBar(SnackBar(content: Text(l.referralRedeemNotEnough)));
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
    final summaryAsync = ref.watch(referralSummaryProvider);
    final cfg = ref.watch(vendorConfigProvider);
    final monthly = cfg.valueOrNull?.priceFor('monthly') ?? 10000;

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
            Padding(
              padding: const EdgeInsets.all(AppTheme.space4),
              child: Text(l.referralEmpty),
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
  });

  final ReferralSummary summary;
  final int monthlyPrice;
  final bool busy;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cur = l.currencySymbol;
    final theme = Theme.of(context);
    final price = monthlyPrice <= 0 ? 10000 : monthlyPrice;
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
              Money(summary.balance).withSymbol(cur),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AppTheme.space2),
            Row(
              children: [
                Icon(Icons.storefront,
                    size: 16, color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 4),
                Text('${l.referralActiveShops}: ${summary.activeReferrals}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer)),
                const Spacer(),
                Text(
                    '${l.referralEarnedTotal}: ${Money(summary.earned).withSymbol(cur)}',
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
                  : l.referralNextGoal(Money(remaining).withSymbol(cur)),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: AppTheme.space3),
            FilledButton.icon(
              onPressed: (busy || !canRedeem) ? null : onRedeem,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.redeem),
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
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text('${i + 1}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer)),
                    ),
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
      error: (_, _) => Text(l.referralEmpty),
      data: (shops) {
        if (shops.isEmpty) return Text(l.referralEmpty);
        final df = DateFormat.yMMMd();
        return Column(
          children: [
            for (final s in shops)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  child: Icon(
                    s.active ? Icons.check : Icons.pause,
                    size: 18,
                  ),
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
