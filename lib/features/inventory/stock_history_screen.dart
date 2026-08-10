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

    return Scaffold(
      appBar: AppBar(
        title: Text(l.stockHistoryTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.space2),
            child: Center(
              child: Text(productName,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        ),
      ),
      body: movements.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.commonUnexpectedError)),
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
                trailing: Text(
                  '${positive ? '+' : ''}${m.qtyDelta}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: color, fontWeight: FontWeight.bold),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
