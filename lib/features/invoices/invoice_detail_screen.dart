import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import '../credit/credit_providers.dart';
import '../credit/credit_repository.dart';
import '../credit/repayment_dialog.dart';
import '../printing/document_print.dart';
import '../printing/print_action.dart';
import '../printing/printing_providers.dart';
import '../staff/staff_providers.dart';
import 'cashier_label.dart';
import 'invoice_capture.dart';
import 'invoice_payment_status.dart';
import 'invoice_pdf.dart';
import 'invoice_view.dart';
import 'receipt_mapper.dart';
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

  /// Captures the already-built [invoice] document as a PNG and opens the
  /// share sheet — the counter's most common post-sale action (send the
  /// invoice to the customer on Viber/Messenger). Orders could always do
  /// this; the finalized-sale record itself couldn't.
  Future<void> _shareInvoiceImage(
    BuildContext context,
    AppLocalizations l,
    InvoiceData invoice,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await captureWidgetAsPng(
        context,
        InvoiceView(data: invoice),
      );
      if (!context.mounted) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice-${invoice.invoiceNo}.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: 'Invoice ${invoice.invoiceNo}',
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l.commonUnexpectedError)),
      );
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
        loading: () => const AppLoadingView(),
        error: (e, _) => EmptyStateView(
          icon: Icons.error_outline,
          title: l.commonUnexpectedError,
          actionLabel: l.commonRetry,
          onAction: () => ref.invalidate(saleDetailProvider(saleId)),
        ),
        data: (d) {
          final s = d.sale;
          final isRefund = s.refundOfSaleId != null;
          final refundRow = refundOf.valueOrNull;
          // This invoice's own shortfall, plus the customer's total credit-book
          // balance (which already includes this invoice, once finalized) —
          // "previous balance" is just the difference, not separately stored.
          //
          // The shortfall MUST come from the credit book's FIFO allocation,
          // not the raw `total - paid`: repayments never mutate the immutable
          // sale row, so raw stayed "unpaid" forever after a customer repaid
          // via the credit book (owner-reported). Same source as the list.
          final owedBySaleMap = ref.watch(creditOwedBySaleProvider);
          final thisOwed = outstandingForDisplay(
            total: s.total,
            paid: s.paid,
            isRefundRow: s.refundOfSaleId != null,
            owedBySaleId: owedBySaleMap,
            saleId: s.id,
          );
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
          final members =
              ref.watch(staffMembersProvider).valueOrNull ?? const [];
          final cashier = cashierNameForSale(
            staffId: s.staffId,
            members: [for (final m in members) (id: m.id, name: m.name)],
            ownerLabel: l.staffRoleOwner,
            deviceLabel: s.deviceId == null
                ? null
                : ref.watch(deviceLabelMapProvider)[s.deviceId],
          );
          const knownMethods = {
            'cash',
            'kbzpay',
            'wavepay',
            'ayapay',
            'cbpay',
            'credit',
            'cod',
            'transfer',
            'split',
          };
          final customName = knownMethods.contains(s.paymentMethod)
              ? null
              : accounts
                    .where((a) => a.id == s.paymentMethod)
                    .map((a) => a.name)
                    .firstOrNull;
          final profile =
              ref.watch(shopProfileProvider).valueOrNull ??
              const ShopProfile(name: '');
          final invoice = invoiceDataFromSale(
            s,
            d.items,
            profile,
            owedBySaleId: owedBySaleMap,
            currencySymbol: currency,
            cashier: cashier,
            paymentMethodCustomName: customName,
            defaultFooter: l.receiptThankYou,
          );
          final docWidth =
              (MediaQuery.sizeOf(context).width - AppTheme.space4 * 2).clamp(
                280.0,
                420.0,
              );
          // The counter flow "customer walks in to pay their credit" used to
          // dead-end here: the balance was shown but the only repayment
          // action lived in Settings → Credit book. Match this sale to its
          // credit-book customer and surface the same dialog right here.
          final CreditCustomer? repayCustomer = thisOwed > 0
              ? ref
                  .watch(creditCustomersProvider)
                  .where(
                    (c) =>
                        c.key ==
                        creditKeyFor(s.customerId, s.customerName ?? ''),
                  )
                  .firstOrNull
              : null;
          return ListView(
            padding: const EdgeInsets.all(AppTheme.space4),
            children: [
              if (reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.space3),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: StatusPill(
                      label: l.invoiceRefunded,
                      tone: StatusTone.critical,
                    ),
                  ),
                ),
              if (isRefund && (s.note ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.space3),
                  child: Text(
                    s.note!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Center(
                child: InvoiceView(data: invoice, width: docWidth),
              ),
              if (thisOwed > 0 || previousBalance > 0) ...[
                const SizedBox(height: AppTheme.space3),
                _Group(
                  children: [
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
                  ],
                ),
                if (repayCustomer != null && repayCustomer.outstanding > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTheme.space3),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () =>
                            showRepaymentDialog(context, repayCustomer),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(l.creditRecordRepayment),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: AppTheme.space5),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      printSaleReceipt(
                        context,
                        ref,
                        sale: s,
                        items: d.items,
                        owedBySaleId: owedBySaleMap,
                      ),
                  icon: const Icon(Icons.print),
                  label: Text(l.invoiceReprint),
                ),
              ),
              const SizedBox(height: AppTheme.space2),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final bytes = await buildInvoicePdf(invoice, l);
                      if (!context.mounted) return;
                      await printPdfDocument(
                        bytes: bytes,
                        name: invoice.invoiceNo,
                      );
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.commonUnexpectedError)),
                      );
                    }
                  },
                  icon: const Icon(Icons.print_outlined),
                  label: Text(l.documentPrint),
                ),
              ),
              const SizedBox(height: AppTheme.space2),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _shareInvoiceImage(context, l, invoice),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(l.invoiceShare),
                ),
              ),
              if (!reversed) ...[
                const SizedBox(height: AppTheme.space3),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
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
