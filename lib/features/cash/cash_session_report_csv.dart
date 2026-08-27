import '../../core/csv_util.dart';
import 'cash_session_repository.dart';

/// A [CashSessionReport] as label/value CSV rows — same figures as
/// `buildCashSessionReportPdf`, for a shop that wants the numbers in a
/// spreadsheet rather than (or alongside) the printable PDF.
String buildCashSessionReportCsv(
  CashSessionReport report, {
  required String openingFloatLabel,
  required String cashSalesLabel,
  required String cashRepaymentsLabel,
  required String expensesLabel,
  required String supplierPaymentsLabel,
  required String expectedCashLabel,
  required String countedCashLabel,
  String? varianceLabel,
  String? varianceText,
  required String lineHeader,
  required String amountHeader,
}) {
  return csvDocument(
    [lineHeader, amountHeader],
    [
      [openingFloatLabel, report.openingAmount],
      [cashSalesLabel, report.cashSalesTotal],
      [cashRepaymentsLabel, report.cashRepaymentsTotal],
      [expensesLabel, -report.expensesTotal],
      [supplierPaymentsLabel, -report.supplierPaymentsTotal],
      [expectedCashLabel, report.expectedCash],
      if (report.closingAmount != null)
        [countedCashLabel, report.closingAmount],
      if (report.closingAmount != null &&
          varianceLabel != null &&
          varianceText != null)
        [varianceLabel, varianceText],
    ],
  );
}
