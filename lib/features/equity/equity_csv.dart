import 'package:intl/intl.dart';

import '../../core/csv_util.dart';
import '../../data/local/database.dart';
import 'equity_calculator.dart';

final _day = DateFormat('yyyy-MM-dd');

/// Owner's Equity as CSV: one row per contribution/drawing, then a summary
/// block (Paid-in Capital / Retained Earnings / Total Equity) appended
/// after — same "data rows, then totals" shape as `buildAgedReceivablesCsv`.
String buildEquityCsv(
  EquitySummary summary,
  List<EquityEntry> entries, {
  required String dateHeader,
  required String typeHeader,
  required String noteHeader,
  required String amountHeader,
  required String contributionLabel,
  required String drawingLabel,
  required String paidInCapitalLabel,
  required String retainedEarningsLabel,
  required String totalEquityLabel,
}) {
  return csvDocument(
    [dateHeader, typeHeader, noteHeader, amountHeader],
    [
      for (final e in entries)
        [
          _day.format(e.date),
          e.type == equityTypeContribution ? contributionLabel : drawingLabel,
          e.note ?? '',
          e.type == equityTypeContribution ? e.amount : -e.amount,
        ],
      ['', '', paidInCapitalLabel, summary.paidInCapital],
      ['', '', retainedEarningsLabel, summary.retainedEarnings],
      ['', '', totalEquityLabel, summary.totalEquity],
    ],
  );
}
