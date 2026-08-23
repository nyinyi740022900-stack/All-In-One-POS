import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../inventory/inventory_providers.dart';
import 'sales_providers.dart';
import 'cart.dart';
import 'scan_sounds.dart';

/// Looks a scanned / typed code up against product barcode or SKU and
/// either adds to the cart or drops the code into Sell search.
void applyScannedSellCode(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l,
  String raw,
) {
  final code = raw.trim();
  if (code.isEmpty || !context.mounted) return;
  final products = ref.read(productsStreamProvider).valueOrNull ?? const [];
  final match = products.firstWhereOrNull((p) {
    final barcode = (p.product.barcode ?? '').trim();
    final sku = (p.product.sku ?? '').trim();
    return barcode == code || sku == code;
  });
  final messenger = ScaffoldMessenger.of(context);
  void feedback(String msg) {
    // Short + floating + queue-clearing: rapid scans replace the previous
    // toast instead of stacking 4-second bars over the checkout button
    // (owner report).
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ));
  }
  if (match != null) {
    unawaited(ScanSounds.instance.success());
    ref.read(cartProvider.notifier).addProduct(match.product);
    if (ref.read(sellSearchProvider).trim() == code) {
      ref.read(sellSearchProvider.notifier).state = '';
    }
    feedback(l.scanAdded(match.product.name));
  } else {
    unawaited(ScanSounds.instance.error());
    ref.read(sellSearchProvider.notifier).state = code;
    feedback(l.scanNotFound(code));
  }
}
