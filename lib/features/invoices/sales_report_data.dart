import '../../data/local/database.dart';

/// One row of a date-range sales report — a thin projection of [Sale] with
/// only what the report prints, so the formatter/PDF/raster renderers don't
/// need to know about Drift types.
class SalesReportRow {
  final String invoiceNo;
  final DateTime date;
  final String customerName;
  final String address;
  final int amount;
  final bool isRefund;

  const SalesReportRow({
    required this.invoiceNo,
    required this.date,
    required this.customerName,
    required this.address,
    required this.amount,
    required this.isRefund,
  });
}

/// A built report: rows newest-first, plus the net total.
class SalesReport {
  final List<SalesReportRow> rows;
  final int total;
  const SalesReport({required this.rows, required this.total});
}

/// Pure: projects [sales] (already date-range-filtered by the caller) into
/// report rows, newest first, plus the net total. A refund is stored as a
/// negative-total [Sale] (see [Sales.refundOfSaleId]), so summing every
/// row's amount already nets refunds out — no special-casing needed.
SalesReport buildSalesReport(List<Sale> sales) {
  final sorted = [...sales]
    ..sort((a, b) => b.finalizedAt.compareTo(a.finalizedAt));
  final rows = [
    for (final s in sorted)
      SalesReportRow(
        invoiceNo: s.invoiceNo,
        date: s.finalizedAt,
        customerName: (s.customerName ?? '').trim(),
        address: (s.deliveryAddress ?? '').trim(),
        amount: s.total,
        isRefund: s.refundOfSaleId != null,
      ),
  ];
  final total = rows.fold<int>(0, (sum, r) => sum + r.amount);
  return SalesReport(rows: rows, total: total);
}
