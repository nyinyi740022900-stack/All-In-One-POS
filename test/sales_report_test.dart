import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/invoices/receipt_data.dart';
import 'package:mm_pos/features/invoices/sales_report_data.dart';
import 'package:mm_pos/features/invoices/sales_report_formatter.dart';

Sale _sale({
  required String id,
  required String invoiceNo,
  required DateTime finalizedAt,
  required int total,
  String? customerName,
  String? deliveryAddress,
  String? refundOfSaleId,
}) {
  return Sale(
    id: id,
    shopId: 'shop-1',
    createdAt: finalizedAt,
    updatedAt: finalizedAt,
    isDeleted: false,
    dirty: false,
    invoiceNo: invoiceNo,
    subtotal: total,
    discount: 0,
    tax: 0,
    total: total,
    paid: total,
    changeDue: 0,
    paymentMethod: 'cash',
    customerName: customerName,
    finalizedAt: finalizedAt,
    deliveryAddress: deliveryAddress,
    refundOfSaleId: refundOfSaleId,
  );
}

void main() {
  group('buildSalesReport', () {
    test('projects sales newest-first with a net total', () {
      final sales = [
        _sale(
            id: 's1',
            invoiceNo: 'INV-001',
            finalizedAt: DateTime(2026, 8, 1),
            total: 1000,
            customerName: 'Aung Aung',
            deliveryAddress: 'Yangon'),
        _sale(
            id: 's2',
            invoiceNo: 'INV-002',
            finalizedAt: DateTime(2026, 8, 2),
            total: 500),
      ];

      final report = buildSalesReport(sales);

      expect(report.rows.map((r) => r.invoiceNo).toList(),
          ['INV-002', 'INV-001']);
      expect(report.rows.last.customerName, 'Aung Aung');
      expect(report.rows.last.address, 'Yangon');
      expect(report.rows.first.address, '');
      expect(report.total, 1500);
    });

    test('nets out a refund (negative-total sale) against the total', () {
      final sales = [
        _sale(
            id: 's1',
            invoiceNo: 'INV-001',
            finalizedAt: DateTime(2026, 8, 1),
            total: 1000),
        _sale(
            id: 'r1',
            invoiceNo: 'RFD-001',
            finalizedAt: DateTime(2026, 8, 2),
            total: -1000,
            refundOfSaleId: 's1'),
      ];

      final report = buildSalesReport(sales);

      expect(report.total, 0);
      expect(report.rows.firstWhere((r) => r.invoiceNo == 'RFD-001').isRefund,
          isTrue);
      expect(report.rows.firstWhere((r) => r.invoiceNo == 'INV-001').isRefund,
          isFalse);
    });
  });

  group('SalesReportFormatter', () {
    test('every line fits within the 58mm width (32 chars)', () {
      final report = buildSalesReport([
        _sale(
            id: 's1',
            invoiceNo: 'INV-20260802-001',
            finalizedAt: DateTime(2026, 8, 2),
            total: 123456,
            customerName: 'A very long customer name indeed',
            deliveryAddress: 'A fairly long delivery address, Yangon'),
      ]);
      final lines = SalesReportFormatter(paper: PaperSize.mm58).format(
        report,
        title: 'Sales report',
        dateRangeLabel: '2026-08-01 → 2026-08-02',
        totalLabel: 'Total',
        noSalesLabel: 'No sales',
      );
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(32),
            reason: 'Line too long: "$line"');
      }
    });

    test('shows the empty-range message when there are no rows', () {
      final report = buildSalesReport(const []);
      final lines = SalesReportFormatter(paper: PaperSize.mm58).format(
        report,
        title: 'Sales report',
        dateRangeLabel: 'All dates',
        totalLabel: 'Total',
        noSalesLabel: 'No sales in this range.',
      );
      expect(lines.any((l) => l.contains('No sales in this range.')), isTrue);
    });

    test('includes the total line with the net amount', () {
      final report = buildSalesReport([
        _sale(
            id: 's1',
            invoiceNo: 'INV-001',
            finalizedAt: DateTime(2026, 8, 1),
            total: 1000),
        _sale(
            id: 's2',
            invoiceNo: 'INV-002',
            finalizedAt: DateTime(2026, 8, 2),
            total: 500),
      ]);
      final lines = SalesReportFormatter(paper: PaperSize.mm80).format(
        report,
        title: 'Sales report',
        dateRangeLabel: 'All dates',
        totalLabel: 'Total',
        noSalesLabel: 'No sales',
      );
      expect(lines.any((l) => l.contains('Total') && l.contains('1,500')),
          isTrue);
    });
  });
}
