import '../../core/csv_util.dart';
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

/// Pure: renders a built report as CSV — for handing off to an accountant
/// or further analysis in a spreadsheet, alongside the existing print/PDF
/// export paths. A trailing "Total" row nets refunds in the same way the
/// on-screen total does (they're just negative-amount rows).
String buildSalesReportCsv(
  SalesReport report, {
  required String invoiceHeader,
  required String dateHeader,
  required String customerHeader,
  required String addressHeader,
  required String amountHeader,
  required String totalLabel,
}) {
  return csvDocument(
    [invoiceHeader, dateHeader, customerHeader, addressHeader, amountHeader],
    [
      for (final r in report.rows)
        [r.invoiceNo, _isoDate(r.date), r.customerName, r.address, r.amount],
      [totalLabel, '', '', '', report.total],
    ],
  );
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
