import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/search_debounce.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../credit/credit_providers.dart';
import '../sell/barcode_scanner_screen.dart';
import '../sell/hardware_scanner_listener.dart';
import '../sell/sales_providers.dart';
import 'invoice_detail_screen.dart';
import 'sales_report_screen.dart';

enum InvoiceFilter { all, credit }

final invoiceFilterProvider = StateProvider<InvoiceFilter>(
  (ref) => InvoiceFilter.all,
);
final invoiceSearchProvider = StateProvider<String>((ref) => '');

/// The query the ledger list consumes — settles [kSearchDebounce] after
/// typing pauses, so a burst of keystrokes refilters the WHOLE sales table
/// (and rebuilds the day groups) once instead of once per character
/// (audit H1). The text field and scan-to-search keep writing to
/// [invoiceSearchProvider]; only this expensive read is debounced.
final debouncedInvoiceSearchProvider =
    debouncedSearchProvider(invoiceSearchProvider);

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key, this.embedded = false});

  /// When true, builds only the list / master–detail body — no [Scaffold] or
  /// [AppBar] (the sales-report action moves to the host) — so
  /// `OrdersInvoicesHubScreen` can host it under its own chrome as a sub-tab.
  /// Default (false) keeps the original standalone full-screen behaviour.
  final bool embedded;

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  String? _selectedSaleId;

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code != null && code.isNotEmpty) {
      ref.read(invoiceSearchProvider.notifier).state = code;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sales = ref.watch(salesStreamProvider);
    final filter = ref.watch(invoiceFilterProvider);
    final query =
        ref.watch(debouncedInvoiceSearchProvider).trim().toLowerCase();
    final owedBySale = ref.watch(creditOwedBySaleProvider);
    final currency = l.currencySymbol;
    final split = isMediumPlus(context);
    int owedOf(Sale s) => owedBySale[s.id] ?? (s.total - s.paid);

    final body = sales.when(
      loading: () => const AppLoadingView(),
      error: (e, _) => ErrorRetryView(
        message: l.commonUnexpectedError,
        onRetry: () => ref.invalidate(salesStreamProvider),
      ),
      data: (all) {
        var list = filter == InvoiceFilter.credit
            ? all.where((s) => owedOf(s) > 0).toList()
            : all;
        if (query.isNotEmpty) {
          list = list
              .where(
                (s) =>
                    s.invoiceNo.toLowerCase().contains(query) ||
                    (s.customerName?.toLowerCase().contains(query) ?? false) ||
                    (s.customerPhone?.toLowerCase().contains(query) ?? false) ||
                    (s.note?.toLowerCase().contains(query) ?? false),
              )
              .toList();
        }

        if (_selectedSaleId != null &&
            !list.any((s) => s.id == _selectedSaleId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedSaleId = null);
          });
        }

        // Day sections over the *filtered* list — "yesterday's takings" is
        // answered by scrolling to one header instead of mentally summing a
        // flat ledger. The stream arrives newest-first, so consecutive runs
        // of the same calendar day are exactly the groups.
        final days = <_DayGroup>[];
        for (final s in list) {
          final f = s.finalizedAt;
          final day = DateTime(f.year, f.month, f.day);
          if (days.isEmpty || days.last.day != day) {
            days.add(_DayGroup(day));
          }
          days.last
            ..sales.add(s)
            ..total += s.total;
        }
        final rows = <Object>[
          for (final d in days) ...[d, ...d.sales],
        ];

        void openSale(Sale s) {
          if (split) {
            setState(() => _selectedSaleId = s.id);
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => InvoiceDetailScreen(saleId: s.id),
              ),
            );
          }
        }

        final listPane = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space3,
                AppTheme.space3,
                AppTheme.space3,
                0,
              ),
              child: _InvoiceSearchField(onScan: _scan),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.space3),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(l.invoiceFilterAll),
                    selected: filter == InvoiceFilter.all,
                    onSelected: (_) =>
                        ref.read(invoiceFilterProvider.notifier).state =
                            InvoiceFilter.all,
                  ),
                  const SizedBox(width: AppTheme.space2),
                  ChoiceChip(
                    label: Text(l.invoiceFilterCredit),
                    selected: filter == InvoiceFilter.credit,
                    onSelected: (_) =>
                        ref.read(invoiceFilterProvider.notifier).state =
                            InvoiceFilter.credit,
                  ),
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? EmptyStateView(
                      icon: Icons.receipt_long_outlined,
                      title: l.invoicesEmpty,
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        if (row is _DayGroup) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTheme.space4,
                              AppTheme.space3,
                              AppTheme.space4,
                              AppTheme.space1,
                            ),
                            child: Row(
                              children: [
                                // Flexes so a long figure beside it can
                                // never push the date off-tile; the total
                                // itself must never ellipsize.
                                Expanded(
                                  child: Text(
                                    DateFormat('dd/MM/yyyy').format(row.day),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontFeatures:
                                              AppTheme.tabularFigures,
                                        ),
                                  ),
                                ),
                                MoneyText(
                                  Money(row.total).withSymbol(currency),
                                  style: Theme.of(context).textTheme.titleSmall,
                                  emphasis: true,
                                ),
                              ],
                            ),
                          );
                        }
                        final s = row as Sale;
                        final owed = owedOf(s);
                        final isCredit = owed > 0;
                        final isRefund = s.refundOfSaleId != null;
                        final customerBits = [
                          if (s.customerName?.trim().isNotEmpty ?? false)
                            s.customerName!.trim(),
                          if (s.customerPhone?.trim().isNotEmpty ?? false)
                            s.customerPhone!.trim(),
                        ].join(' · ');
                        final selected = split && s.id == _selectedSaleId;
                        return ListTile(
                          // Stable per-sale key (audit Low): day groups shift
                          // as new sales land — match by identity, not
                          // position.
                          key: ValueKey('sale-${s.id}'),
                          selected: selected,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          title: Row(
                            children: [
                              // Expanded, not loose-Flexible: on a narrow
                              // device at large text scale the trailing
                              // totals squeeze this row hard, and an
                              // unconstrained pill + unflexed number
                              // overflowed it in testing. The invoice no
                              // ellipsizes; the pill's own label wraps to
                              // two lines when it has to.
                              Expanded(
                                child: Text(
                                  s.invoiceNo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isRefund) ...[
                                const SizedBox(width: AppTheme.space2),
                                Flexible(
                                  child: StatusPill(
                                    label: l.invoiceRefunded,
                                    tone: StatusTone.critical,
                                  ),
                                ),
                              ] else if (isCredit) ...[
                                const SizedBox(width: AppTheme.space2),
                                // `isCredit` is `owed > 0`, so this pill
                                // only ever marks an *outstanding* credit
                                // sale — money still to collect, which is
                                // routine follow-up (attention), not an
                                // error (the old badge painted it
                                // `colorScheme.error` red).
                                Flexible(
                                  child: StatusPill(
                                    label: l.paymentCredit,
                                    tone: StatusTone.attention,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            customerBits.isNotEmpty
                                ? '${DateFormat('yyyy-MM-dd HH:mm').format(s.finalizedAt)} · $customerBits'
                                : DateFormat(
                                    'yyyy-MM-dd HH:mm',
                                  ).format(s.finalizedAt),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Money(s.total).withSymbol(currency),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              if (isCredit && owed > 0)
                                Text(
                                  l.invoiceOwed(
                                    Money(owed).withSymbol(currency),
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        // Same fact as the attention-tone
                                        // credit pill on the left — money
                                        // still to collect, routine
                                        // follow-up, not an error. The two
                                        // marks must agree.
                                        color:
                                            AppColors.of(context).warning,
                                      ),
                                ),
                            ],
                          ),
                          onTap: () => openSale(s),
                        );
                      },
                    ),
            ),
          ],
        );

        if (!split) return listPane;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: widthClassOf(context) == AppWidthClass.expanded ? 42 : 45,
              child: listPane,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              flex: widthClassOf(context) == AppWidthClass.expanded ? 58 : 55,
              child: _selectedSaleId == null
                  ? EmptyStateView(
                      icon: Icons.receipt_outlined,
                      title: l.invoicesSelectHint,
                    )
                  : InvoiceDetailScreen(
                      saleId: _selectedSaleId!,
                      embedded: true,
                    ),
            ),
          ],
        );
      },
    );

    if (widget.embedded) return body;

    return HardwareScannerListener(
      onScan: (code) =>
          ref.read(invoiceSearchProvider.notifier).state = code.trim(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.navInvoices),
          actions: [
            IconButton(
              tooltip: l.salesReportTitle,
              icon: const Icon(Icons.summarize_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SalesReportScreen()),
              ),
            ),
          ],
        ),
        body: body,
      ),
    );
  }
}

/// One calendar day's slice of the ledger — a section header row (date +
/// that day's net total) plus the sales under it.
class _DayGroup {
  _DayGroup(this.day);
  final DateTime day;
  final List<Sale> sales = [];
  int total = 0;
}

class _InvoiceSearchField extends ConsumerStatefulWidget {
  const _InvoiceSearchField({required this.onScan});
  final VoidCallback onScan;

  @override
  ConsumerState<_InvoiceSearchField> createState() =>
      _InvoiceSearchFieldState();
}

class _InvoiceSearchFieldState extends ConsumerState<_InvoiceSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(invoiceSearchProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.listen<String>(invoiceSearchProvider, (prev, next) {
      if (next != _controller.text) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: l.invoiceSearchHint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner),
          tooltip: l.invoiceScanToSearch,
          onPressed: widget.onScan,
        ),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onChanged: (v) => ref.read(invoiceSearchProvider.notifier).state = v,
    );
  }
}
