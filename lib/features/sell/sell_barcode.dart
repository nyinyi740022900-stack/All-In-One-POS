import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../inventory/inventory_providers.dart';
import 'sales_providers.dart';
import 'cart.dart';

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
  if (match != null) {
    ref.read(cartProvider.notifier).addProduct(match.product);
    if (ref.read(sellSearchProvider).trim() == code) {
      ref.read(sellSearchProvider.notifier).state = '';
    }
    messenger.showSnackBar(
      SnackBar(content: Text(l.scanAdded(match.product.name))),
    );
  } else {
    ref.read(sellSearchProvider.notifier).state = code;
    messenger.showSnackBar(SnackBar(content: Text(l.scanNotFound(code))));
  }
}
