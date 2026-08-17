import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import '../invoices/receipt_mapper.dart';
import '../sell/payment_labels.dart';
import 'printing_providers.dart';

/// Prints (or reprints) a receipt for the given sale. Returns silently after
/// showing a snackbar with the outcome. Safe to call from any screen.
Future<void> printSaleReceipt(
  BuildContext context,
  WidgetRef ref, {
  required Sale sale,
  required List<SaleItem> items,
}) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final settings = ref.read(settingsRepositoryProvider);

  try {
    final config = await settings.printerConfig();
    if (!config.hasPrinter) {
      messenger.showSnackBar(SnackBar(content: Text(l.printerNone)));
      return;
    }

    final shop = await ref.read(shopProfileProvider.future);
    final accounts = ref.read(paymentAccountsProvider).valueOrNull;
    final data = receiptFromSale(
      sale,
      items,
      shop,
      paymentMethodLabel:
          paymentLabel(l, sale.paymentMethod, accounts: accounts),
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
  } catch (_) {
    // Honor the documented contract even when a step before the actual
    // print call throws (e.g. Bluetooth turned off mid-lookup) — a caller
    // like checkout relies on this never propagating, since the sale it's
    // reporting on has already committed by the time this runs.
    messenger.showSnackBar(SnackBar(content: Text(l.printFailed)));
  }
}
