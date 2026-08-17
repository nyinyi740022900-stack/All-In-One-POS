import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'inventory_providers.dart';

String stockMovementTypeLabel(AppLocalizations l, String type) => switch (type) {
      'opening' => l.stockMovementOpening,
      'sale' => l.stockMovementSale,
      'return' => l.stockMovementReturn,
      'purchase' => l.stockMovementPurchase,
      'adjustment' => l.stockMovementAdjustment,
      _ => type,
    };

IconData stockMovementTypeIcon(String type) => switch (type) {
      'opening' => Icons.play_circle_outline,
      'sale' => Icons.point_of_sale,
      'return' => Icons.undo,
      'purchase' => Icons.add_box_outlined,
      'adjustment' => Icons.tune,
      _ => Icons.circle_outlined,
    };

class StockHistoryScreen extends ConsumerWidget {
  const StockHistoryScreen(
      {super.key, required this.productId, required this.productName});

  final String productId;
  final String productName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final movements = ref.watch(stockMovementsProvider(productId));
    final subtitleStyle = Theme.of(context).textTheme.bodySmall;
    // The bar used to be a hard `Size.fromHeight(20)` around a `bodySmall`
    // line that is 13 x 1.55 = 20.2pt *before* its 8pt padding and before any
    // text scaling — so the product name was clipped on every visit, and a
    // long Myanmar name at 1.3x lost most of itself. Sized from the real
    // (scaled) line box instead, with room for the second line those names
    // routinely need.
    final lineHeight = MediaQuery.textScalerOf(context)
            .scale(subtitleStyle?.fontSize ?? 13) *
        (subtitleStyle?.height ?? 1.55);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.stockHistoryTitle),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(lineHeight * 2 + AppTheme.space2),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.space4, 0, AppTheme.space4, AppTheme.space2),
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                productName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: subtitleStyle,
              ),
            ),
          ),
        ),
      ),
      body: movements.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetryView(
          message: l.commonUnexpectedError,
          onRetry: () => ref.invalidate(stockMovementsProvider(productId)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyStateView(
              icon: Icons.history,
              title: l.stockHistoryEmpty,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = list[i];
              final positive = m.qtyDelta > 0;
              final color = positive
                  ? AppColors.of(context).success
                  : Theme.of(context).colorScheme.error;
              return ListTile(
                leading: Icon(stockMovementTypeIcon(m.type)),
                title: Text(stockMovementTypeLabel(l, m.type)),
                subtitle: Text(
                  [
                    DateFormat('yyyy-MM-dd HH:mm').format(m.createdAt),
                    if ((m.note ?? '').isNotEmpty) m.note!,
                  ].join(' · '),
                ),
                // Tabular: this is a right-aligned column of signed
                // quantities, and proportional digits make "+1 / +12 / -100"
                // wobble against each other line to line.
                trailing: MoneyText(
                  '${positive ? '+' : ''}${m.qtyDelta}',
                  style: Theme.of(context).textTheme.titleSmall,
                  color: color,
                  emphasis: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
