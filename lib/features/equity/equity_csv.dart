import 'package:intl/intl.dart';

import '../../core/csv_util.dart';
import '../../core/money.dart';
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
  int exponent = 0,
}) {
  String fmt(int minor) => formatMinorUnitsPlain(minor, exponent: exponent);
  return csvDocument(
    [dateHeader, typeHeader, noteHeader, amountHeader],
    [
      for (final e in entries)
        [
          _day.format(e.date),
          e.type == equityTypeContribution ? contributionLabel : drawingLabel,
          e.note ?? '',
          fmt(e.type == equityTypeContribution ? e.amount : -e.amount),
        ],
      ['', '', paidInCapitalLabel, fmt(summary.paidInCapital)],
      ['', '', retainedEarningsLabel, fmt(summary.retainedEarnings)],
      ['', '', totalEquityLabel, fmt(summary.totalEquity)],
    ],
  );
}
