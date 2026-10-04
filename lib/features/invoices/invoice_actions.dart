import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import '../printing/document_print.dart';
import '../printing/print_action.dart';
import '../printing/printing_providers.dart';
import '../settings/device_label_providers.dart';
import '../staff/staff_providers.dart';
import '../credit/credit_providers.dart';
import 'cashier_label.dart';
import 'invoice_capture.dart';
import 'invoice_pdf.dart';
import 'invoice_view.dart';
import 'receipt_mapper.dart';

/// Captures the already-built [invoice] document as a PNG and opens the share
/// sheet — the counter's most common post-sale action (send the invoice to the
/// customer on Viber/Messenger). Shared by the invoice detail screen and the
/// sale-complete panel so both use one code path.
Future<void> shareInvoiceImage(
  BuildContext context,
  AppLocalizations l,
  InvoiceData invoice,
) async {
  final messenger = ScaffoldMessenger.of(context);
  // iPad presents the share sheet as a popover and throws unless it gets a
  // non-empty anchor rect (this made Share fail silently on tablets). Anchor
  // to the calling widget's box.
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  try {
    final bytes = await captureWidgetAsPng(context, InvoiceView(data: invoice));
    if (!context.mounted) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/invoice-${invoice.invoiceNo}.png');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        subject: 'Invoice ${invoice.invoiceNo}',
        sharePositionOrigin: origin,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
  }
}

/// Builds the [InvoiceData] for a just-finalized sale from current provider
/// state (one-shot reads) — what the invoice detail screen builds inline.
Future<InvoiceData> invoiceDataForFinalizedSale(
  WidgetRef ref,
  AppLocalizations l,
  Sale sale,
  List<SaleItem> items,
  String localeCode,
) async {
  final currency = ref.read(shopCurrencyProvider);
  final accounts = ref.read(paymentAccountsProvider).valueOrNull ?? const [];
  final members = ref.read(staffMembersProvider).valueOrNull ?? const [];
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
  final customName = knownMethods.contains(sale.paymentMethod)
      ? null
      : accounts
            .where((a) => a.id == sale.paymentMethod)
            .map((a) => a.name)
            .firstOrNull;
  final profile = await ref.read(shopProfileProvider.future);
  return invoiceDataFromSale(
    sale,
    items,
    profile,
    owedBySaleId: ref.read(creditOwedBySaleProvider),
    currencySymbol: currency.label(localeCode),
    exponent: currency.exponent,
    cashier: cashierNameForSale(
      staffId: sale.staffId,
      members: [for (final m in members) (id: m.id, name: m.name)],
      ownerLabel: l.staffRoleOwner,
      deviceLabel: sale.deviceId == null
          ? null
          : ref.read(deviceLabelMapProvider)[sale.deviceId],
    ),
    paymentMethodCustomName: customName,
    defaultFooter: l.receiptThankYou,
  );
}

/// Print for the sale-complete panel: the paired thermal printer when one is
/// configured (the existing [printSaleReceipt] path), otherwise the system
/// print dialog with the invoice PDF (the detail screen's "Print" path).
Future<void> printFinalizedSale(
  BuildContext context,
  WidgetRef ref, {
  required Sale sale,
  required List<SaleItem> items,
}) async {
  final l = AppLocalizations.of(context);
  final localeCode = Localizations.localeOf(context).languageCode;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final config = await ref.read(settingsRepositoryProvider).printerConfig();
    if (!context.mounted) return;
    if (config.hasPrinter) {
      await printSaleReceipt(context, ref, sale: sale, items: items);
      return;
    }
    final invoice = await invoiceDataForFinalizedSale(
      ref,
      l,
      sale,
      items,
      localeCode,
    );
    final bytes = await buildInvoicePdf(invoice, l);
    await printPdfDocument(bytes: bytes, name: invoice.invoiceNo);
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
  }
}
