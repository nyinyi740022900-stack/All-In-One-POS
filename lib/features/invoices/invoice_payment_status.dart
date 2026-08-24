import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';

/// What this sale still owes **for display**.
///
/// Credit-book repayments live in a separate append-only table
/// (`credit_payments`) — sale rows are immutable, so raw `total - paid`
/// stays stale forever after a customer repays via the credit book. The
/// credit book's FIFO allocation (`creditOwedBySaleProvider`) is the source
/// of truth; surfaces that have it must pass it here. The raw difference is
/// only the fallback for contexts without the map (e.g. right at checkout,
/// before any repayment could exist).
int outstandingForDisplay({
  required int total,
  required int paid,
  required bool isRefundRow,
  Map<String, int>? owedBySaleId,
  String? saleId,
}) {
  // Refund ledger rows negate their figures and are reversed wholesale —
  // the Refunded badge owns their story, never the credit allocation.
  if (!isRefundRow &&
      saleId != null &&
      owedBySaleId != null &&
      owedBySaleId.containsKey(saleId)) {
    final v = owedBySaleId[saleId]!;
    return v < 0 ? 0 : v;
  }
  final raw = total - paid;
  return raw < 0 ? 0 : raw;
}

/// `paid` / `partial` / `unpaid` from a sale's tendered amount vs total.
///
/// `paid >= total` covers a zero-total invoice (comped / fully discounted)
/// as paid, so it does not fall through to unpaid just because nothing
/// changed hands.
///
/// [outstanding] — when the caller has the credit-book FIFO allocation for
/// this sale, pass it here: the sale's *effective* paid becomes
/// `total - outstanding`, so a fully-repaid credit invoice reads `paid`
/// instead of staying `unpaid` beside its stale raw column.
String invoicePaymentStatusCode({
  required int paid,
  required int total,
  int? outstanding,
}) {
  final effectivePaid = outstanding == null ? paid : total - outstanding;
  // Refund ledger rows negate both sides (see SalesRepository.refundSale).
  // Compare magnitudes so a refund of an unpaid credit sale (paid 0,
  // total -1000) is unpaid, not paid — `0 >= -1000` would have lied.
  if (total < 0 || effectivePaid < 0) {
    final magPaid = effectivePaid.abs();
    final magTotal = total.abs();
    if (magPaid >= magTotal) return 'paid';
    if (magPaid > 0) return 'partial';
    return 'unpaid';
  }
  if (effectivePaid >= total) return 'paid';
  if (effectivePaid > 0) return 'partial';
  return 'unpaid';
}

(String label, StatusTone tone) invoicePaymentStatusDisplay(
  AppLocalizations l,
  String status,
) =>
    switch (status) {
      'paid' => (l.invoiceStatusPaid, StatusTone.positive),
      'partial' => (l.invoiceStatusPartial, StatusTone.attention),
      // Web-storefront order stages — a pre-sale document, not a credit
      // debt. The old fall-through stamped both red "unpaid", telling a
      // customer who had just sent a transfer screenshot that they owed
      // money, and reading "အကြွေးကျန်" (credit) on a COD order that was
      // never credit at all.
      'cod_pending' => (
        l.invoiceStatusPayOnDelivery,
        StatusTone.neutral,
      ),
      'transfer_pending' => (
        l.invoiceStatusAwaitingConfirmation,
        StatusTone.attention,
      ),
      _ => (l.invoiceStatusUnpaid, StatusTone.critical),
    };

/// True for the two web-order stages that are awaiting something normal
/// (a COD handover, a transfer verification) rather than money the customer
/// is withholding. Surfaces use this to hold back the "amount due" row —
/// the total already says the figure, and "ကျန်ငွေ" beside it reads as a
/// debt collector's note.
bool isPendingOrderPaymentStatus(String status) =>
    status == 'cod_pending' || status == 'transfer_pending';
