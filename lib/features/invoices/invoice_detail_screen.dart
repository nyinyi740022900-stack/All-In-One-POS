import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import '../credit/credit_providers.dart';
import '../printing/print_action.dart';
import 'receipt_data.dart';
import '../sell/payment_labels.dart';
import '../sell/sales_providers.dart';
import '../settings/device_label_providers.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({
    super.key,
    required this.saleId,
    this.embedded = false,
  });

  final String saleId;

  /// Inline pane on tablets — no route AppBar back affordance needed.
  final bool embedded;

  Future<void> _refund(BuildContext context, WidgetRef ref, String no) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.invoiceRefundConfirmTitle),
        content: Text(l.invoiceRefundConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.invoiceRefund),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final result = await ref.read(salesRepositoryProvider).refundSale(saleId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.invoiceRefundSuccess(result.invoiceNo))),
      );
    } on StateError {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.invoiceAlreadyRefunded)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final detail = ref.watch(saleDetailProvider(saleId));
    final refundOf = ref.watch(refundOfProvider(saleId));
    final currency = l.currencySymbol;
    final accounts = ref.watch(paymentAccountsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: embedded
          ? AppBar(
              title: Text(l.invoiceDetail),
              automaticallyImplyLeading: false,
            )
          : AppBar(title: Text(l.invoiceDetail)),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.commonUnexpectedError)),
        data: (d) {
          final s = d.sale;
          final isRefund = s.refundOfSaleId != null;
          final refundRow = refundOf.valueOrNull;
          // This invoice's own shortfall, plus the customer's total credit-book
          // balance (which already includes this invoice, once finalized) —
          // "previous balance" is just the difference, not separately stored.
          final thisOwed = s.total > s.paid ? s.total - s.paid : 0;
          var totalOutstanding = thisOwed;
          if (s.customerId != null) {
            for (final c in ref.watch(creditCustomersProvider)) {
              if (c.customerId == s.customerId) {
                totalOutstanding = c.outstanding;
                break;
              }
            }
          }
          final previousBalance = totalOutstanding - thisOwed;
          return ListView(
            padding: const EdgeInsets.all(AppTheme.space4),
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      s.invoiceNo,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (isRefund || refundRow != null) ...[
                    const SizedBox(width: AppTheme.space2),
                    _RefundBadge(label: l.invoiceRefunded),
                  ],
                ],
              ),
              Text(DateFormat('yyyy-MM-dd HH:mm').format(s.finalizedAt)),
              if (isRefund)
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.space1),
                  child: Text(
                    s.note ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (s.customerName != null && s.customerName!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.space2),
                  child: _row(context, l.receiptCustomer, s.customerName!),
                ),
              if (s.customerPhone != null && s.customerPhone!.trim().isNotEmpty)
                _row(context, l.receiptPhone, s.customerPhone!),
              if (s.deliveryAddress != null &&
                  s.deliveryAddress!.trim().isNotEmpty)
                _row(context, l.orderDeliveryAddress, s.deliveryAddress!),
              const Divider(height: AppTheme.space5),
              ...d.items.map((it) {
                final itemDiscount = lineDiscountOf(
                  unitPrice: it.priceSnapshot,
                  qty: it.qty,
                  lineTotal: it.lineTotal,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.space1,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${it.nameSnapshot}\n${it.qty} x ${Money(it.priceSnapshot).formatted}',
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(Money(it.lineTotal).withSymbol(currency)),
                          if (itemDiscount > 0)
                            Text(
                              '-${Money(itemDiscount).withSymbol(currency)}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: AppTheme.space5),
              _row(
                context,
                l.sellSubtotal,
                Money(s.subtotal).withSymbol(currency),
              ),
              if (s.discount > 0)
                _row(
                  context,
                  l.sellDiscount,
                  '-${Money(s.discount).withSymbol(currency)}',
                ),
              _row(
                context,
                l.commonTotal,
                Money(s.total).withSymbol(currency),
                bold: true,
              ),
              _row(
                context,
                l.sellPaymentMethod,
                paymentLabel(l, s.paymentMethod, accounts: accounts),
              ),
              if (thisOwed > 0) ...[
                _row(
                  context,
                  l.creditDeposit,
                  Money(s.paid).withSymbol(currency),
                ),
                _row(
                  context,
                  l.creditBalanceDue,
                  Money(thisOwed).withSymbol(currency),
                  bold: true,
                ),
              ],
              if (previousBalance > 0) ...[
                _row(
                  context,
                  l.creditPreviousBalance,
                  Money(previousBalance).withSymbol(currency),
                ),
                _row(
                  context,
                  l.creditTotalBalanceDue,
                  Money(totalOutstanding).withSymbol(currency),
                  bold: true,
                ),
              ],
              if (s.deviceId != null)
                _row(
                  context,
                  l.invoiceDevice,
                  ref.watch(deviceLabelMapProvider)[s.deviceId] ??
                      l.invoiceDeviceUnnamed,
                ),
              const SizedBox(height: AppTheme.space5),
              Center(
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: s.invoiceNo,
                  width: 220,
                  height: 60,
                  drawText: true,
                ),
              ),
              const SizedBox(height: AppTheme.space5),
              FilledButton.icon(
                onPressed: () =>
                    printSaleReceipt(context, ref, sale: s, items: d.items),
                icon: const Icon(Icons.print),
                label: Text(l.invoiceReprint),
              ),
              if (!isRefund && refundRow == null) ...[
                const SizedBox(height: AppTheme.space3),
                OutlinedButton.icon(
                  onPressed: () => _refund(context, ref, s.invoiceNo),
                  icon: const Icon(Icons.undo),
                  label: Text(l.invoiceRefund),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) {
    final style = bold
        ? Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space2,
        vertical: AppTheme.space1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
