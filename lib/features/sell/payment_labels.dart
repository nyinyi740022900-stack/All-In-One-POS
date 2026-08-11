import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';

/// Maps a payment method code to its localized display label. The 4
/// default Payment Accounts (`kbzpay`/`wavepay`/`ayapay`/`cbpay`) keep
/// resolving through this switch regardless of [accounts] — they're
/// seeded with these exact fixed ids precisely so old sales/receipts
/// never need a lookup. A custom account (an id the switch doesn't know)
/// resolves its own name from [accounts] when the caller supplies it;
/// callers that don't (a different value space entirely, e.g. license
/// renewal payments or storefront orders) keep the old cash fallback.
String paymentLabel(AppLocalizations l, String method,
    {List<PaymentAccount>? accounts}) {
  switch (method) {
    case 'kbzpay':
      return l.paymentKbzPay;
    case 'wavepay':
      return l.paymentWavePay;
    case 'ayapay':
      return l.paymentAyaPay;
    case 'cbpay':
      return l.paymentCbPay;
    case 'credit':
      return l.paymentCredit;
    case 'cod':
      return l.paymentCod;
    case 'cash':
      return l.paymentCash;
    default:
      final account =
          accounts?.where((a) => a.id == method).firstOrNull;
      return account?.name ?? l.paymentCash;
  }
}

/// The glyph that goes with [paymentLabel] for the same method code. Payment
/// choice is one of the highest-frequency taps in a sale and it happens while
/// a customer is waiting, so the options carry an icon as well as a label:
/// the shape is recognizable at a glance and in bad light, which matters more
/// than reading a word — especially for Myanmar labels, which are longer and
/// harder to scan than their English equivalents.
///
/// Grouped by *kind of money movement*, not by brand, so a custom account the
/// shop adds later still lands somewhere sensible instead of needing its own
/// icon: cash in hand, a phone wallet, pay-later, cash-on-delivery, other.
IconData paymentIcon(String method) => switch (method) {
  'cash' => Icons.payments_outlined,
  'kbzpay' || 'wavepay' || 'ayapay' || 'cbpay' => Icons.smartphone_outlined,
  'credit' => Icons.schedule_outlined,
  'cod' => Icons.local_shipping_outlined,
  _ => Icons.account_balance_wallet_outlined,
};
