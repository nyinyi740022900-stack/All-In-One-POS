import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/equity/equity_calculator.dart';

void main() {
  group('computeEquitySummary (pure)', () {
    EquityEntry entry(String type, int amount) => EquityEntry(
          id: 'eq-$type-$amount',
          shopId: 'shop-1',
          type: type,
          amount: amount,
          date: DateTime(2026, 7, 1),
          createdAt: DateTime(2026, 7, 1),
          updatedAt: DateTime(2026, 7, 1),
          isDeleted: false,
          dirty: false,
        );

    test('paid-in capital = contributions - drawings', () {
      final result = computeEquitySummary(
        entries: [
          entry(equityTypeContribution, 500000),
          entry(equityTypeDrawing, 100000),
        ],
        cumulativeNetProfit: 0,
      );
      expect(result.paidInCapital, 400000);
    });

    test('retained earnings passes cumulative net profit straight through', () {
      final result = computeEquitySummary(
        entries: const [],
        cumulativeNetProfit: 250000,
      );
      expect(result.retainedEarnings, 250000);
    });

    test('total equity = paid-in capital + retained earnings', () {
      final result = computeEquitySummary(
        entries: [entry(equityTypeContribution, 300000)],
        cumulativeNetProfit: 150000,
      );
      expect(result.totalEquity, 450000);
    });

    test('a net loss (negative cumulative profit) reduces total equity', () {
      final result = computeEquitySummary(
        entries: [entry(equityTypeContribution, 300000)],
        cumulativeNetProfit: -50000,
      );
      expect(result.totalEquity, 250000);
    });
  });
}
