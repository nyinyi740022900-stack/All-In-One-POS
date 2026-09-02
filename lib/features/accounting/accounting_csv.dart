import 'package:intl/intl.dart';

import '../../core/csv_util.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../suppliers/accounts_payable.dart';
import 'cash_flow_calculator.dart';
import 'credit_aging.dart';

final _day = DateFormat('yyyy-MM-dd');

/// The Credit book's aged ledger, one row per still-owed sale, oldest
/// first — what an accountant asks for when chasing debts. [bucketLabels]
/// carries the four localized bucket names ("0–30 days" … "90+ days").
String buildAgedReceivablesCsv(
  List<AgedReceivable> rows,
  List<int> totals, {
  required List<String> bucketLabels,
  required String customerHeader,
  required String phoneHeader,
  required String invoiceHeader,
  required String dateHeader,
  required String daysHeader,
  required String bucketHeader,
  required String outstandingHeader,
  int exponent = 0,
}) {
  return csvDocument(
    [
      customerHeader,
      phoneHeader,
      invoiceHeader,
      dateHeader,
      daysHeader,
      bucketHeader,
      outstandingHeader,
    ],
    [
      for (final r in rows)
        [
          r.customerName,
          r.phone ?? '',
          r.invoiceNo,
          _day.format(r.finalizedAt),
          DateTime.now().difference(r.finalizedAt).inDays,
          bucketLabels[r.bucket],
          formatMinorUnitsPlain(r.outstanding, exponent: exponent),
        ],
      // Summary block: one total per bucket, so the file stands alone.
      for (var i = 0; i < totals.length; i++)
        [
          bucketLabels[i],
          '',
          '',
          '',
          '',
          '',
          formatMinorUnitsPlain(totals[i], exponent: exponent),
        ],
    ],
  );
}

/// Accounts Payable, one row per supplier with a balance.
String buildAccountsPayableCsv(
  List<SupplierBalance> balances, {
  required String supplierHeader,
  required String billedHeader,
  required String paidHeader,
  required String outstandingHeader,
  int exponent = 0,
}) {
  return csvDocument(
    [supplierHeader, billedHeader, paidHeader, outstandingHeader],
    [
      for (final s in balances)
        [
          s.name,
          formatMinorUnitsPlain(s.billed, exponent: exponent),
          formatMinorUnitsPlain(s.paid, exponent: exponent),
          formatMinorUnitsPlain(s.outstanding, exponent: exponent),
        ],
    ],
  );
}

/// The Expenses list as CSV — the period the screen is showing. [accountNameById]
/// resolves the paying account; a null accountId (legacy/cash) prints empty.
String buildExpensesCsv(
  List<Expense> expenses, {
  required Map<String, String> accountNameById,
  required String Function(String category) categoryLabel,
  required String dateHeader,
  required String categoryHeader,
  required String amountHeader,
  required String accountHeader,
  required String noteHeader,
  int exponent = 0,
}) {
  return csvDocument(
    [dateHeader, categoryHeader, amountHeader, accountHeader, noteHeader],
    [
      for (final e in expenses)
        [
          _day.format(e.date),
          categoryLabel(e.category),
          formatMinorUnitsPlain(e.amount, exponent: exponent),
          e.accountId == null ? '' : (accountNameById[e.accountId!] ?? ''),
          e.note ?? '',
        ],
    ],
  );
}

/// Balance Sheet as label/value rows, in statement order.
String buildBalanceSheetCsv(
  List<(String, int)> rows, {
  required String labelHeader,
  required String amountHeader,
  int exponent = 0,
}) {
  return csvDocument(
    [labelHeader, amountHeader],
    [
      for (final r in rows)
        [r.$1, formatMinorUnitsPlain(r.$2, exponent: exponent)],
    ],
  );
}

/// Cash Flow as one block per account: opening, in, out, closing.
String buildCashFlowCsv(
  List<AccountCashFlow> flows, {
  required String accountHeader,
  required String openingHeader,
  required String inflowHeader,
  required String outflowHeader,
  required String closingHeader,
  int exponent = 0,
}) {
  return csvDocument(
    [
      accountHeader,
      openingHeader,
      inflowHeader,
      outflowHeader,
      closingHeader,
    ],
    [
      for (final f in flows)
        [
          f.name,
          formatMinorUnitsPlain(f.opening, exponent: exponent),
          formatMinorUnitsPlain(f.inflow, exponent: exponent),
          formatMinorUnitsPlain(f.outflow, exponent: exponent),
          formatMinorUnitsPlain(f.closing, exponent: exponent),
        ],
    ],
  );
}
