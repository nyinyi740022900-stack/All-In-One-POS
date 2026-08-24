import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import 'inventory_providers.dart';
import 'stock_history_screen.dart';
import 'stock_movements_csv.dart';

/// Every movement type a shop's stock ledger can have, in the order shown
/// as filter chips.
///
/// `opening` is in this list even though it isn't in the *default* selection:
/// it was missing entirely before, so an opening-balance row could only be
/// seen by de-selecting every chip (the provider treats an empty set as "no
/// type filter"). That made the chip row a lie — ticking all of them still
/// hid rows — and left the new "show all" action unable to do what it says.
const _allMovementTypes = [
  'purchase',
  'adjustment',
  'sale',
  'return',
  'opening',
];

/// Shop-wide stock movement history (Inventory tab's "Stock history" icon) —
/// unlike [StockHistoryScreen], which is scoped to one product from its
/// editor, this spans every product with a type filter (defaulting to
/// restocks + adjustments — sales/returns are already visible via Invoices),
/// a date-range picker, and a by-product name filter.
class StockMovementsScreen extends ConsumerStatefulWidget {
  const StockMovementsScreen({super.key});

  @override
  ConsumerState<StockMovementsScreen> createState() =>
      _StockMovementsScreenState();
}

class _StockMovementsScreenState extends ConsumerState<StockMovementsScreen> {
  late final TextEditingController _productSearch;

  @override
  void initState() {
    super.initState();
    _productSearch = TextEditingController(
      text: ref.read(movementProductSearchProvider),
    );
  }

  @override
  void dispose() {
    _productSearch.dispose();
    super.dispose();
  }

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

  /// Shares the CURRENTLY FILTERED ledger as CSV — the file can never
  /// disagree with what the screen is showing. Premium-gated like the
  /// inventory CSV export.
  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    if (!ref.read(isPremiumProvider)) {
      await showPremiumRequiredDialog(
        context,
        l.stockHistoryExportCsv,
        benefit: l.stockHistoryCsvBenefit,
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final movements = ref.read(filteredMovementsProvider);
    try {
      final csv = buildStockMovementsCsv(
        movements,
        dateHeader: l.stockHistoryHeaderDate,
        productHeader: l.productName,
        typeHeader: l.stockHistoryHeaderType,
        qtyChangeHeader: l.stockHistoryHeaderQtyChange,
        unitCostHeader: l.stockHistoryHeaderUnitCost,
        noteHeader: l.stockHistoryHeaderNote,
        typeLabel: (t) => stockMovementTypeLabel(l, t),
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/stock-history.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: l.stockHistoryTitle,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final movements = ref.watch(filteredMovementsProvider);
    final start = ref.watch(movementStartDateProvider);
    final end = ref.watch(movementEndDateProvider);
    final types = ref.watch(movementTypeFilterProvider);
    final productQuery = ref.watch(movementProductSearchProvider).trim();
    // The "show all" action and programmatic clears write the provider
    // directly — mirror the value back into the field (same pattern the
    // Inventory search field uses).
    ref.listen<String>(movementProductSearchProvider, (prev, next) {
      if (next != _productSearch.text) {
        _productSearch.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });
    final df = DateFormat('yyyy-MM-dd HH:mm');
    // Any filter that could be hiding rows — a date range, a product-name
    // fragment, or a type set that isn't "everything" (which includes the
    // default).
    final narrowed = start != null ||
        end != null ||
        productQuery.isNotEmpty ||
        !_allMovementTypes.every(types.contains);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.stockHistoryTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: l.stockHistoryExportCsv,
            onPressed: () => _exportCsv(context, ref),
          ),
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
                TextField(
                  controller: _productSearch,
                  decoration: InputDecoration(
                    hintText: l.stockHistoryFilterProduct,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    suffixIcon: productQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => ref
                                .read(movementProductSearchProvider.notifier)
                                .state = '',
                          ),
                  ),
                  onChanged: (v) => ref
                      .read(movementProductSearchProvider.notifier)
                      .state = v,
                ),
                const SizedBox(height: AppTheme.space2),
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
                // The filters *start* narrowed (restocks + adjustments only,
                // by design), and a date range or product filter narrows them
                // further — so a bare "no stock history" was routinely telling
                // the owner their ledger was empty when it was only hidden,
                // with no way out of the dead end. Say which, and offer the
                // way out.
                ? EmptyStateView(
                    icon: narrowed ? Icons.filter_alt_off_outlined : Icons.history,
                    title: l.stockHistoryEmpty,
                    message: narrowed ? l.stockHistoryEmptyFiltered : null,
                    actionLabel: narrowed ? l.stockHistoryShowAll : null,
                    onAction: narrowed
                        ? () {
                            ref.read(movementTypeFilterProvider.notifier).state =
                                _allMovementTypes.toSet();
                            ref.read(movementStartDateProvider.notifier).state =
                                null;
                            ref.read(movementEndDateProvider.notifier).state =
                                null;
                            ref
                                .read(movementProductSearchProvider.notifier)
                                .state = '';
                          }
                        : null,
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
                          // Two lines, not one: the Myanmar movement labels
                          // ("ပြင်ဆင်ခြင်း", "အဝယ်စာရင်း") plus a 16-character
                          // timestamp already fill a phone line by
                          // themselves, so a single line ellipsized away the
                          // shopkeeper's own note every time they wrote one.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: MoneyText(
                          '${positive ? '+' : ''}${m.qtyDelta}',
                          style: Theme.of(context).textTheme.titleSmall,
                          color: color,
                          emphasis: true,
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
