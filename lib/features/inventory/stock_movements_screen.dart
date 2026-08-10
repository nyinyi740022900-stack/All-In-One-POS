import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'inventory_providers.dart';
import 'stock_history_screen.dart';

/// Every movement type a shop's stock ledger can have, in the order shown
/// as filter chips.
const _allMovementTypes = ['purchase', 'adjustment', 'sale', 'return'];

/// Shop-wide stock movement history (Inventory tab's "Stock history" icon) —
/// unlike [StockHistoryScreen], which is scoped to one product from its
/// editor, this spans every product with a type filter (defaulting to
/// restocks + adjustments — sales/returns are already visible via Invoices)
/// and a date-range picker.
class StockMovementsScreen extends ConsumerWidget {
  const StockMovementsScreen({super.key});

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final start = ref.read(movementStartDateProvider);
    final end = ref.read(movementEndDateProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: start != null && end != null
          ? DateTimeRange(
              start: start, end: end.subtract(const Duration(days: 1)))
          : null,
    );
    if (picked == null) return;
    ref.read(movementStartDateProvider.notifier).state =
        DateTime(picked.start.year, picked.start.month, picked.start.day);
    ref.read(movementEndDateProvider.notifier).state = DateTime(
            picked.end.year, picked.end.month, picked.end.day)
        .add(const Duration(days: 1));
  }

  String _rangeLabel(DateTime start, DateTime endExclusive) {
    final df = DateFormat('yyyy-MM-dd');
    final inclusiveEnd = endExclusive.subtract(const Duration(days: 1));
    return '${df.format(start)} → ${df.format(inclusiveEnd)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final movements = ref.watch(filteredMovementsProvider);
    final start = ref.watch(movementStartDateProvider);
    final end = ref.watch(movementEndDateProvider);
    final types = ref.watch(movementTypeFilterProvider);
    final df = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(l.stockHistoryTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_outlined),
            tooltip: l.stockHistoryPickDateRange,
            onPressed: () => _pickRange(context, ref),
          ),
          if (start != null && end != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: l.stockHistoryClearDateRange,
              onPressed: () {
                ref.read(movementStartDateProvider.notifier).state = null;
                ref.read(movementEndDateProvider.notifier).state = null;
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.space4,
                AppTheme.space3, AppTheme.space4, AppTheme.space2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (start != null && end != null) ...[
                  Text(_rangeLabel(start, end),
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: AppTheme.space2),
                ],
                Wrap(
                  spacing: AppTheme.space2,
                  runSpacing: AppTheme.space2,
                  children: [
                    for (final t in _allMovementTypes)
                      FilterChip(
                        label: Text(stockMovementTypeLabel(l, t)),
                        selected: types.contains(t),
                        onSelected: (selected) {
                          final next = {...types};
                          if (selected) {
                            next.add(t);
                          } else {
                            next.remove(t);
                          }
                          ref.read(movementTypeFilterProvider.notifier).state =
                              next;
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: movements.isEmpty
                ? EmptyStateView(
                    icon: Icons.history,
                    title: l.stockHistoryEmpty,
                  )
                : ListView.separated(
                    itemCount: movements.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final mp = movements[i];
                      final m = mp.movement;
                      final positive = m.qtyDelta > 0;
                      final color = positive
                          ? AppColors.of(context).success
                          : Theme.of(context).colorScheme.error;
                      return ListTile(
                        leading: Icon(stockMovementTypeIcon(m.type)),
                        title: Text(mp.productName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            stockMovementTypeLabel(l, m.type),
                            df.format(m.createdAt),
                            if ((m.note ?? '').isNotEmpty) m.note!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          '${positive ? '+' : ''}${m.qtyDelta}',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  color: color, fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
