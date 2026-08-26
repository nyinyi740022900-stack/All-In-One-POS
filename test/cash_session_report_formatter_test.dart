import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/cash/cash_session_report_formatter.dart';
import 'package:mm_pos/features/cash/cash_session_repository.dart';
import 'package:mm_pos/features/invoices/receipt_data.dart';

void main() {
  const report = CashSessionReport(
    openingAmount: 50000,
    cashSalesTotal: 85000,
    cashRepaymentsTotal: 5000,
    expensesTotal: 12000,
    supplierPaymentsTotal: 3000,
    expectedCash: 125000,
    closingAmount: 124500,
    variance: -500,
  );

  List<String> format({int? closingAmount, int? variance}) {
    return CashSessionReportFormatter(paper: PaperSize.mm58).format(
      CashSessionReport(
        openingAmount: report.openingAmount,
        cashSalesTotal: report.cashSalesTotal,
        cashRepaymentsTotal: report.cashRepaymentsTotal,
        expensesTotal: report.expensesTotal,
        supplierPaymentsTotal: report.supplierPaymentsTotal,
        expectedCash: report.expectedCash,
        closingAmount: closingAmount,
        variance: variance,
      ),
      title: 'Cash Session Report',
      openedLabel: 'Opened',
      closedLabel: 'Closed',
      openingFloatLabel: 'Opening float',
      cashSalesLabel: 'Cash sales',
      cashRepaymentsLabel: 'Cash repayments',
      expensesLabel: 'Expenses',
      supplierPaymentsLabel: 'Supplier payments',
      expectedCashLabel: 'Expected cash',
      countedCashLabel: 'Counted cash',
      openedAt: DateTime(2026, 8, 1, 9),
      closedAt: closingAmount == null ? null : DateTime(2026, 8, 1, 20),
      varianceLabel: 'Variance',
      varianceText: variance == null ? null : 'Short by 500 Ks',
    );
  }

  test('every line fits within the 58mm width (32 chars)', () {
    final lines = format(closingAmount: 124500, variance: -500);
    for (final l in lines) {
      for (final sub in l.split('\n')) {
        expect(sub.length, lessThanOrEqualTo(32));
      }
    }
  });

  test('includes opening/cash sales/repayments/expenses/supplier payments/expected',
      () {
    final lines = format(closingAmount: 124500, variance: -500).join('\n');
    expect(lines, contains('Opening float'));
    expect(lines, contains('50,000 Ks'));
    expect(lines, contains('Cash sales'));
    expect(lines, contains('85,000 Ks'));
    expect(lines, contains('Cash repayments'));
    expect(lines, contains('5,000 Ks'));
    expect(lines, contains('Expenses'));
    expect(lines, contains('-12,000 Ks'));
    expect(lines, contains('Supplier payments'));
    expect(lines, contains('-3,000 Ks'));
    expect(lines, contains('Expected cash'));
    expect(lines, contains('125,000 Ks'));
  });

  test('counted cash and variance only appear once the session is closed',
      () {
    final openLines = format().join('\n');
    expect(openLines, isNot(contains('Counted cash')));
    expect(openLines, isNot(contains('Variance')));

    final closedLines = format(closingAmount: 124500, variance: -500).join('\n');
    expect(closedLines, contains('Counted cash'));
    expect(closedLines, contains('124,500 Ks'));
    expect(closedLines, contains('Variance'));
    expect(closedLines, contains('Short by 500 Ks'));
  });

  test('does not include a "Closed" line for a still-open session', () {
    final lines = format().join('\n');
    expect(lines, isNot(contains('Closed')));
  });
}
