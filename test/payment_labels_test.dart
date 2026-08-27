import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/sell/payment_labels.dart';
import 'package:mm_pos/l10n/app_localizations_en.dart';

void main() {
  final l = AppLocalizationsEn();

  test('paymentLabel resolves split to its own label, not the cash fallback',
      () {
    // Before adding an explicit case, an unrecognized method code silently
    // fell through to the cash label — exactly wrong for a split sale.
    expect(paymentLabel(l, 'split'), l.paymentSplit);
    expect(paymentLabel(l, 'split'), isNot(l.paymentCash));
  });

  test('paymentIcon gives split its own glyph, not the generic wallet icon',
      () {
    expect(paymentIcon('split'), Icons.call_split);
  });
}
