import '../../core/csv_util.dart';
import 'analytics_calculator.dart';

/// A formal Profit & Loss layout for a date range — the same figures
/// [AnalyticsSummary] already computes (revenue, COGS, gross profit, net
/// profit), plus the one thing it doesn't break out: expenses by category.
class PnlStatement {
  final DateTime start;
  final DateTime end;
  final int revenue;
  final int cogs;
  final int grossProfit;
  final Map<String, int> expensesByCategory;
  final int totalExpenses;
  final int netProfit;

  const PnlStatement({
    required this.start,
    required this.end,
    required this.revenue,
    required this.cogs,
    required this.grossProfit,
    required this.expensesByCategory,
    required this.totalExpenses,
    required this.netProfit,
  });
}

/// Pure: combines an already-computed [AnalyticsSummary] with a per-category
/// expense breakdown into a [PnlStatement]. Trivial — [summary] already has
/// every figure except the breakdown itself.
PnlStatement buildPnlStatement(
  AnalyticsSummary summary, {
  required Map<String, int> expensesByCategory,
  required DateTime start,
  required DateTime end,
}) {
  return PnlStatement(
    start: start,
    end: end,
    revenue: summary.revenue,
    cogs: summary.cost,
    grossProfit: summary.profit,
    expensesByCategory: expensesByCategory,
    totalExpenses: summary.expenses,
    netProfit: summary.netProfit,
  );
}

/// Pure: renders a [PnlStatement] as CSV for handing off to an accountant,
/// alongside the print/PDF export paths — same shape as `buildSalesReportCsv`.
String buildPnlCsv(
  PnlStatement p, {
  required String lineHeader,
  required String amountHeader,
  required String revenueLabel,
  required String cogsLabel,
  required String grossProfitLabel,
  required String totalExpensesLabel,
  required String netProfitLabel,
  required String Function(String category) categoryLabel,
}) {
  return csvDocument(
    [lineHeader, amountHeader],
    [
      [revenueLabel, p.revenue],
      [cogsLabel, -p.cogs],
      [grossProfitLabel, p.grossProfit],
      for (final entry in p.expensesByCategory.entries)
        if (entry.value != 0) [categoryLabel(entry.key), -entry.value],
      [totalExpensesLabel, -p.totalExpenses],
      [netProfitLabel, p.netProfit],
    ],
  );
}
