import '../../data/local/database.dart';

/// Which 30-day slice a receivable has aged into — index into the four
/// bucket labels the Credit screen renders and the CSV carries.
///
/// 0 = 0–30 days, 1 = 31–60, 2 = 61–90, 3 = 90+. Age counts from the
/// sale's `finalizedAt` (the day the debt was incurred), not the last
/// repayment — a part-paid 100-day-old debt is still a 90+ debt.
int agingBucketFor(DateTime finalizedAt, DateTime now) {
  final days = now.difference(finalizedAt).inDays;
  if (days <= 30) return 0;
  if (days <= 60) return 1;
  if (days <= 90) return 2;
  return 3;
}

/// One still-owed credit sale with its age bucket.
class AgedReceivable {
  final String saleId;
  final String invoiceNo;
  final String customerName;
  final String? phone;
  final DateTime finalizedAt;
  final int outstanding;
  final int bucket;

  const AgedReceivable({
    required this.saleId,
    required this.invoiceNo,
    required this.customerName,
    this.phone,
    required this.finalizedAt,
    required this.outstanding,
    required this.bucket,
  });
}

/// Pure: the receivables ledger as aged rows, oldest bucket last. Only rows
/// that still owe something appear; refund rows (negated totals) and debts
/// already cleared by the FIFO repayment allocation drop out via
/// `outstanding <= 0`.
List<AgedReceivable> ageReceivables({
  required List<Sale> creditSales,
  required Map<String, int> owedBySaleId,
  required DateTime now,
}) {
  final rows = <AgedReceivable>[];
  for (final s in creditSales) {
    final raw = owedBySaleId[s.id] ?? (s.total - s.paid);
    final outstanding = raw < 0 ? 0 : raw;
    if (outstanding <= 0) continue;
    rows.add(
      AgedReceivable(
        saleId: s.id,
        invoiceNo: s.invoiceNo,
        customerName: (s.customerName ?? '').trim().isEmpty
            ? s.invoiceNo
            : s.customerName!.trim(),
        phone: s.customerPhone,
        finalizedAt: s.finalizedAt,
        outstanding: outstanding,
        bucket: agingBucketFor(s.finalizedAt, now),
      ),
    );
  }
  rows.sort((a, b) => a.finalizedAt.compareTo(b.finalizedAt));
  return rows;
}

/// Σ outstanding per bucket — the four figures the Credit screen's aging
/// strip shows and the CSV's summary block carries.
List<int> agingTotals(List<AgedReceivable> rows) {
  final totals = List<int>.filled(4, 0);
  for (final r in rows) {
    totals[r.bucket] += r.outstanding;
  }
  return totals;
}
