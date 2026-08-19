import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';

/// `paid` / `partial` / `unpaid` from a sale's tendered amount vs total.
///
/// `paid >= total` covers a zero-total invoice (comped / fully discounted)
/// as paid, so it does not fall through to unpaid just because nothing
/// changed hands.
String invoicePaymentStatusCode({required int paid, required int total}) {
  // Refund ledger rows negate both sides (see SalesRepository.refundSale).
  // Compare magnitudes so a refund of an unpaid credit sale (paid 0,
  // total -1000) is unpaid, not paid — `0 >= -1000` would have lied.
  if (total < 0 || paid < 0) {
    final magPaid = paid.abs();
    final magTotal = total.abs();
    if (magPaid >= magTotal) return 'paid';
    if (magPaid > 0) return 'partial';
    return 'unpaid';
  }
  if (paid >= total) return 'paid';
  if (paid > 0) return 'partial';
  return 'unpaid';
}

(String label, StatusTone tone) invoicePaymentStatusDisplay(
  AppLocalizations l,
  String status,
) =>
    switch (status) {
      'paid' => (l.invoiceStatusPaid, StatusTone.positive),
      'partial' => (l.invoiceStatusPartial, StatusTone.attention),
      _ => (l.invoiceStatusUnpaid, StatusTone.critical),
    };
