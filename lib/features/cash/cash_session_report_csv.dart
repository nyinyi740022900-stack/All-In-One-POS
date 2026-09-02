import '../../core/csv_util.dart';
import '../../core/money.dart';
import 'cash_session_repository.dart';

/// A [CashSessionReport] as label/value CSV rows — same figures as
/// `buildCashSessionReportPdf`, for a shop that wants the numbers in a
/// spreadsheet rather than (or alongside) the printable PDF.
String buildCashSessionReportCsv(
  CashSessionReport report, {
  required String openingFloatLabel,
  required String cashSalesLabel,
  required String cashRepaymentsLabel,
  required String topUpsLabel,
  required String expensesLabel,
  required String supplierPaymentsLabel,
  required String expectedCashLabel,
  required String countedCashLabel,
  String? varianceLabel,
  String? varianceText,
  required String lineHeader,
  required String amountHeader,
  int exponent = 0,
}) {
  String fmt(int minor) => formatMinorUnitsPlain(minor, exponent: exponent);
  return csvDocument(
    [lineHeader, amountHeader],
    [
      [openingFloatLabel, fmt(report.openingAmount)],
      [cashSalesLabel, fmt(report.cashSalesTotal)],
      [cashRepaymentsLabel, fmt(report.cashRepaymentsTotal)],
      [topUpsLabel, fmt(report.topUpsTotal)],
      [expensesLabel, fmt(-report.expensesTotal)],
      [supplierPaymentsLabel, fmt(-report.supplierPaymentsTotal)],
      [expectedCashLabel, fmt(report.expectedCash)],
      if (report.closingAmount != null)
        [countedCashLabel, fmt(report.closingAmount!)],
      if (report.closingAmount != null &&
          varianceLabel != null &&
          varianceText != null)
        [varianceLabel, varianceText],
    ],
  );
}
