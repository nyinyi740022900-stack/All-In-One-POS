import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/cash/cash_session_report_csv.dart';
import 'package:mm_pos/features/cash/cash_session_repository.dart';

void main() {
  const openReport = CashSessionReport(
    openingAmount: 50000,
    cashSalesTotal: 85000,
    cashRepaymentsTotal: 5000,
    topUpsTotal: 4000,
    expensesTotal: 12000,
    supplierPaymentsTotal: 3000,
    expectedCash: 125000,
    closingAmount: null,
    variance: null,
  );

  const closedReport = CashSessionReport(
    openingAmount: 50000,
    cashSalesTotal: 85000,
    cashRepaymentsTotal: 5000,
    topUpsTotal: 4000,
    expensesTotal: 12000,
    supplierPaymentsTotal: 3000,
    expectedCash: 125000,
    closingAmount: 124500,
    variance: -500,
  );

  String csv(CashSessionReport report,
          {String? varianceLabel, String? varianceText}) =>
      buildCashSessionReportCsv(
        report,
        openingFloatLabel: 'Opening float',
        cashSalesLabel: 'Cash sales',
        cashRepaymentsLabel: 'Cash repayments',
        topUpsLabel: 'Cash top-ups',
        expensesLabel: 'Expenses',
        supplierPaymentsLabel: 'Supplier payments',
        expectedCashLabel: 'Expected cash',
        countedCashLabel: 'Counted cash',
        varianceLabel: varianceLabel,
        varianceText: varianceText,
        lineHeader: 'Line',
        amountHeader: 'Amount',
      );

  group('buildCashSessionReportCsv', () {
    test('an open (uncounted) session omits the counted/variance rows', () {
      final lines = csv(openReport).split('\r\n');
      expect(lines[0], 'Line,Amount');
      expect(lines, contains('Opening float,50000'));
      expect(lines, contains('Cash sales,85000'));
      expect(lines, contains('Cash repayments,5000'));
      expect(lines, contains('Cash top-ups,4000'));
      expect(lines, contains('Expenses,-12000'));
      expect(lines, contains('Supplier payments,-3000'));
      expect(lines.last, 'Expected cash,125000');
      expect(lines.any((l) => l.contains('Counted')), isFalse);
    });

    test('a closed session appends counted cash and the variance line', () {
      final lines = csv(
        closedReport,
        varianceLabel: 'Variance',
        varianceText: 'Short by 500 Ks',
      ).split('\r\n');
      expect(lines, contains('Counted cash,124500'));
      expect(lines.last, 'Variance,Short by 500 Ks');
    });

    test('expenses and supplier payments render negative (money out)', () {
      final lines = csv(openReport).split('\r\n');
      expect(lines.any((l) => l.startsWith('Expenses,-')), isTrue);
      expect(
          lines.any((l) => l.startsWith('Supplier payments,-')), isTrue);
    });
  });
}
