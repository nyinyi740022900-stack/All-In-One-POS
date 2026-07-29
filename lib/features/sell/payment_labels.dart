import '../../l10n/app_localizations.dart';

/// Maps a payment method code to its localized display label.
String paymentLabel(AppLocalizations l, String method) {
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
    default:
      return l.paymentCash;
  }
}
