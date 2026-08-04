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
