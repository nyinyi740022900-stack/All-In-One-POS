import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../credit/credit_providers.dart';
import '../sell/barcode_scanner_screen.dart';
import '../sell/sales_providers.dart';
import 'invoice_detail_screen.dart';
import 'sales_report_screen.dart';

enum InvoiceFilter { all, credit }

final invoiceFilterProvider =
    StateProvider<InvoiceFilter>((ref) => InvoiceFilter.all);
final invoiceSearchProvider = StateProvider<String>((ref) => '');

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final code = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
    if (code != null && code.isNotEmpty) {
      ref.read(invoiceSearchProvider.notifier).state = code;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sales = ref.watch(salesStreamProvider);
    final filter = ref.watch(invoiceFilterProvider);
    final query = ref.watch(invoiceSearchProvider).trim().toLowerCase();
    final owedBySale = ref.watch(creditOwedBySaleProvider);
    final currency = l.currencySymbol;
    // Owed after repayments have been allocated to this invoice.
    int owedOf(Sale s) => owedBySale[s.id] ?? (s.total - s.paid);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navInvoices),
        actions: [
          IconButton(
            tooltip: l.salesReportTitle,
            icon: const Icon(Icons.summarize_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SalesReportScreen(),
            )),
          ),
        ],
      ),
      body: sales.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) {
          var list = filter == InvoiceFilter.credit
              ? all.where((s) => owedOf(s) > 0).toList()
              : all;
          if (query.isNotEmpty) {
            list = list
                .where((s) =>
                    s.invoiceNo.toLowerCase().contains(query) ||
                    (s.customerName?.toLowerCase().contains(query) ?? false) ||
                    (s.customerPhone?.toLowerCase().contains(query) ?? false) ||
                    // A Social Order converted to this sale was handed to
                    // the customer as an invoice showing the *order*
                    // number (generated before conversion, unrelated to
                    // this sale's own invoiceNo) — `note` carries
                    // "Order {orderNo}" (see OrdersRepository.convertToSale),
                    // so searching/scanning that original number still
                    // finds the sale here.
                    (s.note?.toLowerCase().contains(query) ?? false))
                .toList();
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppTheme.space3,
                    AppTheme.space3, AppTheme.space3, 0),
                child: _InvoiceSearchField(onScan: () => _scan(context, ref)),
              ),
              Padding(
                padding: const EdgeInsets.all(AppTheme.space3),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(l.invoiceFilterAll),
                      selected: filter == InvoiceFilter.all,
                      onSelected: (_) => ref
                          .read(invoiceFilterProvider.notifier)
                          .state = InvoiceFilter.all,
                    ),
                    const SizedBox(width: AppTheme.space2),
                    ChoiceChip(
                      label: Text(l.invoiceFilterCredit),
                      selected: filter == InvoiceFilter.credit,
                      onSelected: (_) => ref
                          .read(invoiceFilterProvider.notifier)
                          .state = InvoiceFilter.credit,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(child: Text(l.invoicesEmpty))
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = list[i];
                          final owed = owedOf(s);
                          final isCredit = owed > 0;
                          final isRefund = s.refundOfSaleId != null;
                          final customerBits = [
                            if (s.customerName?.trim().isNotEmpty ?? false)
                              s.customerName!.trim(),
                            if (s.customerPhone?.trim().isNotEmpty ?? false)
                              s.customerPhone!.trim(),
                          ].join(' · ');
                          return ListTile(
                            title: Row(
                              children: [
                                Flexible(child: Text(s.invoiceNo)),
                                if (isRefund) ...[
                                  const SizedBox(width: 6),
                                  _RefundBadge(label: l.invoiceRefunded),
                                ] else if (isCredit) ...[
                                  const SizedBox(width: 6),
                                  _CreditBadge(
                                      settled: owed <= 0, label: l.paymentCredit),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              customerBits.isNotEmpty
                                  ? '${DateFormat('yyyy-MM-dd HH:mm').format(s.finalizedAt)} · $customerBits'
                                  : DateFormat('yyyy-MM-dd HH:mm')
                                      .format(s.finalizedAt),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  Money(s.total).withSymbol(currency),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                if (isCredit && owed > 0)
                                  Text(
                                    l.invoiceOwed(
                                        Money(owed).withSymbol(currency)),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            Theme.of(context).colorScheme.error),
                                  ),
                              ],
                            ),
                            onTap: () =>
                                Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  InvoiceDetailScreen(saleId: s.id),
                            )),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CreditBadge extends StatelessWidget {
  const _CreditBadge({required this.settled, required this.label});
  final bool settled;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = settled ? Colors.green : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

class _RefundBadge extends StatelessWidget {
  const _RefundBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
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
