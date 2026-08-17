import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
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
            // Reversing a finalized sale is irreversible and appends a
            // reversal to an immutable ledger — it must not wear the same
            // brand-green affirmative as "Save".
            style: AppTheme.dangerFilledButtonStyle(ctx),
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
    } catch (e) {
      // Any other failure (e.g. a DB/transaction error mid-refund) — the
      // StateError branch above only covers the "already refunded" case.
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
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
        error: (e, _) => EmptyStateView(
          icon: Icons.error_outline,
          title: l.commonUnexpectedError,
        ),
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
          final colors = AppColors.of(context);
          final reversed = isRefund || refundRow != null;
          return ListView(
            padding: const EdgeInsets.all(AppTheme.space4),
            children: [
              // --- Who/when: the identity of this receipt ---
              _Group(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.invoiceNo,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontFeatures: AppTheme.tabularFigures,
                                  ),
                            ),
                            Text(
                              DateFormat(
                                'yyyy-MM-dd HH:mm',
                              ).format(s.finalizedAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (reversed) ...[
                        const SizedBox(width: AppTheme.space2),
                        StatusPill(
                          label: l.invoiceRefunded,
                          tone: StatusTone.critical,
                        ),
                      ],
                    ],
                  ),
                  if (isRefund && (s.note ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppTheme.space1),
                      child: Text(
                        s.note!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (s.customerName != null &&
                      s.customerName!.trim().isNotEmpty) ...[
                    const SizedBox(height: AppTheme.space2),
                    SummaryRow(
                      l.receiptCustomer,
                      s.customerName!,
                      isMoney: false,
                    ),
                  ],
                  if (s.customerPhone != null &&
                      s.customerPhone!.trim().isNotEmpty)
                    SummaryRow(l.receiptPhone, s.customerPhone!,
                        isMoney: false),
                  if (s.deliveryAddress != null &&
                      s.deliveryAddress!.trim().isNotEmpty)
                    SummaryRow(
                      l.orderDeliveryAddress,
                      s.deliveryAddress!,
                      isMoney: false,
                    ),
                ],
              ),
              const SizedBox(height: AppTheme.space3),

              // --- What was sold ---
              _Group(
                children: [
                  for (var i = 0; i < d.items.length; i++) ...[
                    if (i > 0) const Divider(height: AppTheme.space4),
                    _ItemLine(
                      item: d.items[i],
                      currency: currency,
                      discount: lineDiscountOf(
                        unitPrice: d.items[i].priceSnapshot,
                        qty: d.items[i].qty,
                        lineTotal: d.items[i].lineTotal,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppTheme.space3),

              // --- What it came to ---
              _Group(
                children: [
                  SummaryRow(
                    l.sellSubtotal,
                    Money(s.subtotal).withSymbol(currency),
                  ),
                  if (s.discount > 0)
                    SummaryRow(
                      l.sellDiscount,
                      '-${Money(s.discount).withSymbol(currency)}',
                      color: colors.danger,
                    ),
                  const Divider(height: AppTheme.space4),
                  SummaryRow(
                    l.commonTotal,
                    Money(s.total).withSymbol(currency),
                    emphasis: true,
                  ),
                  SummaryRow(
                    l.sellPaymentMethod,
                    paymentLabel(l, s.paymentMethod, accounts: accounts),
                    isMoney: false,
                  ),
                  if (thisOwed > 0) ...[
                    SummaryRow(
                      l.creditDeposit,
                      Money(s.paid).withSymbol(currency),
                    ),
                    SummaryRow(
                      l.creditBalanceDue,
                      Money(thisOwed).withSymbol(currency),
                      emphasis: true,
                      color: colors.danger,
                    ),
                  ],
                  if (previousBalance > 0) ...[
                    SummaryRow(
                      l.creditPreviousBalance,
                      Money(previousBalance).withSymbol(currency),
                    ),
                    SummaryRow(
                      l.creditTotalBalanceDue,
                      Money(totalOutstanding).withSymbol(currency),
                      emphasis: true,
                      color: colors.danger,
                    ),
                  ],
                  if (s.deviceId != null)
                    SummaryRow(
                      l.invoiceDevice,
                      ref.watch(deviceLabelMapProvider)[s.deviceId] ??
                          l.invoiceDeviceUnnamed,
                      isMoney: false,
                    ),
                ],
              ),
              const SizedBox(height: AppTheme.space4),

              // A Code128 is black bars on white by definition — on the dark
              // theme it was painting near-black on near-black, both
              // invisible and unscannable. It gets its own white plate in
              // both brightnesses, like the paper receipt it stands in for.
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppTheme.space3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: s.invoiceNo,
                    width: 220,
                    height: 60,
                    drawText: true,
                    color: Colors.black,
                    style: const TextStyle(color: Colors.black, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.space5),
              FilledButton.icon(
                onPressed: () =>
                    printSaleReceipt(context, ref, sale: s, items: d.items),
                icon: const Icon(Icons.print),
                label: Text(l.invoiceReprint),
              ),
              if (!reversed) ...[
                const SizedBox(height: AppTheme.space3),
                OutlinedButton.icon(
                  // Secondary *and* destructive: outlined keeps it
                  // subordinate to Reprint, the danger tone keeps it from
                  // reading as just another neutral option.
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.danger,
                    side: BorderSide(color: colors.danger),
                  ),
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
}

/// One boxed group of related rows. The screen used to be a single flat
/// column of 15+ rows separated by two dividers, so "who bought it", "what
/// they bought" and "what it came to" all read as one undifferentiated list.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// A sold line: name, then `qty × unit price` as a muted second line, then the
/// line total right-aligned and tabular — the same shape as the checkout
/// sheet's cart lines, so the receipt reads as a replay of the sale.
///
/// Was `Text('$name\n$qty x $price')` — one string with a newline in it, which
/// meant the quantity carried the same weight as the product name and none of
/// the money on this screen lined up.
class _ItemLine extends StatelessWidget {
  const _ItemLine({
    required this.item,
    required this.currency,
    required this.discount,
  });

  final SaleItem item;
  final String currency;
  final int discount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.nameSnapshot, style: theme.textTheme.bodyLarge),
              Text(
                '${item.qty} × ${Money(item.priceSnapshot).withSymbol(currency)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: AppTheme.tabularFigures,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppTheme.space3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MoneyText(Money(item.lineTotal).withSymbol(currency)),
            if (discount > 0)
              MoneyText(
                '-${Money(discount).withSymbol(currency)}',
                style: theme.textTheme.bodySmall,
                color: colors.danger,
              ),
          ],
        ),
      ],
    );
  }
}

