import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../invoices/invoice_capture.dart';
import '../invoices/invoice_view.dart';
import '../invoices/receipt_mapper.dart';
import '../printing/printing_providers.dart';
import '../storefront/storefront_screen.dart' show storefrontRepositoryProvider;
import 'order_labels.dart';

/// Builds a polished invoice image for an order and opens the share sheet so
/// the shop can save it (Photos/Files) or send it to the customer
/// (Viber/Messenger).
///
/// Works for any order (social or storefront) — an order isn't a finalized
/// sale yet, so this renders from the order + its items, not the append-only
/// sales ledger.
Future<void> shareOrderInvoice(
  BuildContext context,
  WidgetRef ref,
  Order order,
  List<OrderItem> items,
) async {
  final l = AppLocalizations.of(context);
  final profile = await ref.read(shopProfileProvider.future);

  // Best-effort: reuse the shop's published storefront logo, if any. Never
  // blocks the invoice on network/offline — falls back to no logo.
  String? logoUrl;
  try {
    final storefront = await ref.read(storefrontRepositoryProvider).mine();
    logoUrl = storefront?.logoUrl;
    if ((logoUrl ?? '').isNotEmpty && context.mounted) {
      await precacheImage(NetworkImage(logoUrl!), context);
    }
  } catch (_) {
    logoUrl = null;
  }

  final data = InvoiceData(
    shopName: profile.name,
    shopLogoUrl: logoUrl,
    shopPhone: profile.phone,
    shopAddress: profile.address,
    invoiceNo: order.orderNo,
    date: order.createdAt,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    deliveryAddress: order.deliveryAddress,
    township: order.township,
    items: [
      for (final it in items)
        InvoiceItemData(
          name: it.nameSnapshot,
          qty: it.qty,
          lineTotal: it.lineTotal,
        ),
    ],
    deliveryFee: order.deliveryFee,
    paymentStatus: order.paymentStatus,
    footer: (profile.footer != null && profile.footer!.isNotEmpty)
        ? profile.footer
        : l.receiptThankYou,
  );

  if (!context.mounted) return;
  final bytes = await captureWidgetAsPng(context, InvoiceView(data: data));

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/invoice-${order.orderNo}.png');
  await file.writeAsBytes(bytes);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      subject: 'Invoice ${order.orderNo}',
    ),
  );
}

/// Prints an order directly to the shop's configured Bluetooth thermal
/// printer — the same ESC/POS pipeline used for finalized sales. Shows a
/// snackbar with the outcome; returns silently if no printer is configured.
Future<void> printOrderInvoice(
  BuildContext context,
  WidgetRef ref,
  Order order,
  List<OrderItem> items,
) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final settings = ref.read(settingsRepositoryProvider);

  final config = await settings.printerConfig();
  if (!config.hasPrinter) {
    messenger.showSnackBar(SnackBar(content: Text(l.printerNone)));
    return;
  }

  final shop = await ref.read(shopProfileProvider.future);
  final data = receiptFromOrder(
    order,
    items,
    shop,
    paymentMethodLabel: orderPaymentLabel(l, order.paymentStatus),
    deliveryFeeLabel: l.orderDeliveryFee,
    defaultFooter: l.receiptThankYou,
  );

  final result = await ref.read(printerServiceProvider).printReceipt(
        data,
        paper: config.paper,
        mac: config.mac!,
        labels: receiptLabels(l),
      );

  messenger.showSnackBar(SnackBar(
    content: Text(result.ok ? l.printSuccess : l.printFailed),
  ));
}
