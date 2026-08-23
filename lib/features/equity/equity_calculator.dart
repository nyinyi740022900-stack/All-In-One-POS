import '../../data/local/database.dart';

const equityTypeContribution = 'contribution';
const equityTypeDrawing = 'drawing';

/// Owner's Equity summary for an eventual Balance Sheet — Paid-in Capital
/// (what the owner has put in vs taken out) plus Retained Earnings
/// (cumulative Net Profit since inception, from the P&L — never stored
/// here, always derived via `AnalyticsRepository.cumulativeNetProfit`).
class EquitySummary {
  final int paidInCapital;
  final int retainedEarnings;

  const EquitySummary({
    required this.paidInCapital,
    required this.retainedEarnings,
  });

  int get totalEquity => paidInCapital + retainedEarnings;
}

/// Pure: Σcontributions − Σdrawings from [entries], combined with
/// [cumulativeNetProfit] (the P&L's `netProfit` computed over an
/// all-time range) into an [EquitySummary].
EquitySummary computeEquitySummary({
  required List<EquityEntry> entries,
  required int cumulativeNetProfit,
}) {
  var paidIn = 0;
  for (final e in entries) {
    if (e.type == equityTypeContribution) {
      paidIn += e.amount;
    } else if (e.type == equityTypeDrawing) {
      paidIn -= e.amount;
    }
  }
  return EquitySummary(
    paidInCapital: paidIn,
    retainedEarnings: cumulativeNetProfit,
  );
}
