import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/analytics/analytics_calculator.dart';
import 'package:mm_pos/features/analytics/pnl_data.dart';
import 'package:mm_pos/features/analytics/pnl_formatter.dart';
import 'package:mm_pos/features/invoices/receipt_data.dart';

const _summary = AnalyticsSummary(
  revenue: 500000,
  salesCount: 20,
  discount: 0,
  cost: 300000,
  stockValue: 0,
  expenses: 45000,
  creditSales: 0,
  creditOutstanding: 0,
  daily: [],
  topProducts: [],
);

void main() {
  group('buildPnlStatement (pure)', () {
    test('revenue/COGS/gross profit pass straight through from the summary',
        () {
      final p = buildPnlStatement(_summary,
          expensesByCategory: const {'rent': 30000, 'utilities': 15000},
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 9, 1));
      expect(p.revenue, 500000);
      expect(p.cogs, 300000);
      expect(p.grossProfit, 200000); // 500000 - 300000
    });

    test('net profit matches AnalyticsSummary.netProfit', () {
      final p = buildPnlStatement(_summary,
          expensesByCategory: const {'rent': 45000},
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 9, 1));
      expect(p.netProfit, _summary.netProfit);
      expect(p.netProfit, 155000); // 200000 gross - 45000 expenses
    });

    test('expensesByCategory carries through unchanged', () {
      final byCategory = {'rent': 30000, 'utilities': 15000, 'wages': 0};
      final p = buildPnlStatement(_summary,
          expensesByCategory: byCategory,
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 9, 1));
      expect(p.expensesByCategory, byCategory);
      expect(p.totalExpenses, 45000);
    });
  });

  group('PnlFormatter', () {
    List<String> format() {
      final p = buildPnlStatement(_summary,
          expensesByCategory: const {'rent': 30000, 'utilities': 15000, 'wages': 0},
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 9, 1));
      return PnlFormatter(paper: PaperSize.mm58).format(
        p,
        title: 'Profit & Loss',
        dateRangeLabel: 'Date range',
        revenueLabel: 'Revenue',
        cogsLabel: 'COGS',
        grossProfitLabel: 'Gross profit',
        totalExpensesLabel: 'Total expenses',
        netProfitLabel: 'Net profit',
        categoryLabel: (c) => c,
      );
    }

    test('every line fits within the 58mm width (32 chars)', () {
      for (final l in format()) {
        for (final sub in l.split('\n')) {
          expect(sub.length, lessThanOrEqualTo(32));
        }
      }
    });

    test('includes revenue/COGS/gross profit/net profit', () {
      final lines = format().join('\n');
      expect(lines, contains('Revenue'));
      expect(lines, contains('500,000 Ks'));
      expect(lines, contains('COGS'));
      expect(lines, contains('-300,000 Ks'));
      expect(lines, contains('Gross profit'));
      expect(lines, contains('200,000 Ks'));
      expect(lines, contains('Net profit'));
      expect(lines, contains('155,000 Ks'));
    });

    test('only non-zero expense categories appear', () {
      final lines = format().join('\n');
      expect(lines, contains('rent'));
      expect(lines, contains('utilities'));
      expect(lines, isNot(contains('wages')));
    });
  });
}
