import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../printing/printing_providers.dart';
import 'cart.dart';
import 'held_sales_provider.dart';

/// The list of parked carts (Sell app bar's bookmark action). Tapping a row
/// resumes it; if another cart is already active, that one is held first —
/// a counter never loses a built cart to a resume, and never faces a
/// dead-end "clear your cart first" dialog mid-rush.
Future<void> showHeldSalesSheet(
  BuildContext context,
  WidgetRef ref, {
  required void Function(CartState cart) onResumed,
}) {
  return showAppModal(
    context: context,
    builder: (_) => _HeldSalesSheet(onResumed: onResumed),
  );
}

class _HeldSalesSheet extends ConsumerWidget {
  const _HeldSalesSheet({required this.onResumed});

  final void Function(CartState cart) onResumed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final held = ref.watch(heldSalesProvider);
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final messenger = ScaffoldMessenger.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space4,
          AppTheme.space2,
          AppTheme.space4,
          AppTheme.space4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.sellHeldTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppTheme.space2),
            if (held.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTheme.space5),
                child: EmptyStateView(
                  icon: Icons.pause_circle_outline,
                  title: l.sellHeldEmpty,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: held.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final h = held[i];
                    final first = h.cart.lines.isEmpty
                        ? null
                        : h.cart.lines.first.product.name;
                    return ListTile(
                      leading: const Icon(Icons.pause_circle_outline),
                      title: Text(
                        first == null
                            ? l.sellCart
                            : '$first${h.cart.lines.length > 1 ? ' …' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${l.checkoutItemsCount(h.itemCount)} · '
                        '${DateFormat('dd/MM HH:mm').format(h.at)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFeatures: AppTheme.tabularFigures,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MoneyText(
                            h.total.withCurrency(currency, locale),
                            style: Theme.of(context).textTheme.titleSmall,
                            emphasis: true,
                          ),
                          IconButton(
                            tooltip: l.commonDelete,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () {
                              ref.read(heldSalesProvider.notifier).remove(h.id);
                              messenger.showSnackBar(
                                SnackBar(content: Text(l.sellHeldRemoved)),
                              );
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        final cart = ref
                            .read(heldSalesProvider.notifier)
                            .resume(h.id);
                        if (cart == null) return;
                        onResumed(cart);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
