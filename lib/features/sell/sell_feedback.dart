import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';

/// The "only N in stock" answer, shared by every stock-capped add/increment
/// call site (Sell grid tap, cart-panel stepper, checkout-sheet stepper) so
/// they can't drift apart.
///
/// Was a bare 1-second text snackbar — too fast to actually read while
/// ringing up the next item, and with no icon to distinguish it at a glance
/// from the "added" confirmations around it. 3 seconds + a warning glyph.
void showStockCapSnackBar(
  BuildContext context,
  AppLocalizations l,
  int qty,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 3),
      content: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: Theme.of(context).colorScheme.onInverseSurface),
          const SizedBox(width: AppTheme.space2),
          Expanded(child: Text(l.sellStockCap(qty))),
        ],
      ),
    ),
  );
}
