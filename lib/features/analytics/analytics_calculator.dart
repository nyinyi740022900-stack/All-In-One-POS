// Pure analytics aggregation — no I/O, no Flutter — so it is fully
// unit-testable. The repository fetches rows from Drift and feeds them here.

typedef SaleRow = ({
  String id,
  int total,
  int paid,
  String paymentMethod,
  int discount,
  DateTime finalizedAt,
  bool isRefund,
});
typedef ItemRow = ({
  String productId,
  String name,
  int qty,
  int lineTotal,
  int? costSnapshot,
});

class DailyRevenue {
  final DateTime day;
  final int revenue;
  const DailyRevenue(this.day, this.revenue);
}

class TopProduct {
  final String productId;
  final String name;
  final int qty;
  final int revenue;
  const TopProduct(
      {required this.productId,
      required this.name,
      required this.qty,
      required this.revenue});
}

class AnalyticsSummary {
  final int revenue;
  final int salesCount;
  final int discount;
  final int cost;
  final int stockValue;
  final int expenses;

  /// Number of credit sales in the range, and the still-unpaid portion of
  /// them (total − paid). `revenue` counts the full billed amount (accrual);
  /// [creditOutstanding] is the slice of that not yet collected.
  final int creditSales;
  final int creditOutstanding;

  final List<DailyRevenue> daily;
  final List<TopProduct> topProducts;

  const AnalyticsSummary({
    required this.revenue,
    required this.salesCount,
    required this.discount,
    required this.cost,
    required this.stockValue,
    required this.expenses,
    required this.creditSales,
    required this.creditOutstanding,
    required this.daily,
    required this.topProducts,
  });

  /// Cash actually collected = billed revenue − outstanding credit.
  int get collected => revenue - creditOutstanding;

  /// Gross profit = net revenue − cost of goods sold. Cost is the FIFO
  /// cost snapshotted at sale time where available (see [ItemRow.costSnapshot]),
  /// falling back to the product's current cost price for older sales. Does
  /// **not** account for rent/utilities/wages/etc — see [netProfit] for that.
  int get profit => revenue - cost;

  /// Gross profit minus non-inventory operating expenses (rent, utilities,
  /// wages, transport, packaging — see the `Expenses` table). This is the
  /// actual bottom line; [profit] alone overstates it by whatever the shop
  /// spent running the business beyond restocking.
  int get netProfit => profit - expenses;

  static const empty = AnalyticsSummary(
    revenue: 0,
    salesCount: 0,
    discount: 0,
    cost: 0,
    stockValue: 0,
    expenses: 0,
    creditSales: 0,
    creditOutstanding: 0,
    daily: [],
    topProducts: [],
  );
}

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

AnalyticsSummary computeAnalytics({
  required List<SaleRow> sales,
  required List<ItemRow> items,
  required Map<String, int> productCost,
  required int stockValue,
  required DateTime start,
  required DateTime end,
  int expenses = 0,
  int topN = 5,

  /// Remaining owed per sale id AFTER repayments are allocated (the same
  /// FIFO map the Credit book uses — CreditRepository.owedBySale). When
  /// supplied, a repaid credit sale no longer counts as outstanding and its
  /// money counts as collected. Absent entries fall back to raw total − paid.
  Map<String, int> creditOwedBySaleId = const {},
}) {
  var revenue = 0;
  var discount = 0;
  var creditSales = 0;
  var creditOutstanding = 0;
  var salesCount = 0;
  final byDay = <DateTime, int>{};
  for (final s in sales) {
    revenue += s.total;
    discount += s.discount;
    if (!s.isRefund) salesCount += 1;
    // Repayment-aware (fix for the Analytics-vs-Credit-book mismatch): use
    // the FIFO allocation when the map knows this sale, else raw difference.
    final override = creditOwedBySaleId[s.id];
    final owed = override ?? (s.total - s.paid);
    if (owed > 0) {
      creditSales += 1;
      creditOutstanding += owed;
    }
    final k = _dayKey(s.finalizedAt);
    byDay[k] = (byDay[k] ?? 0) + s.total;
  }

  var cost = 0;
  final qtyByProduct = <String, int>{};
  final revByProduct = <String, int>{};
  final nameByProduct = <String, String>{};
  for (final it in items) {
    cost += it.costSnapshot ?? it.qty * (productCost[it.productId] ?? 0);
    qtyByProduct[it.productId] = (qtyByProduct[it.productId] ?? 0) + it.qty;
    revByProduct[it.productId] =
        (revByProduct[it.productId] ?? 0) + it.lineTotal;
    nameByProduct[it.productId] = it.name;
  }

  final top = qtyByProduct.keys
      .map((id) => TopProduct(
            productId: id,
            name: nameByProduct[id] ?? id,
            qty: qtyByProduct[id]!,
            revenue: revByProduct[id] ?? 0,
          ))
      .toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));

  // Continuous daily series across the whole range (zero-filled).
  final daily = <DailyRevenue>[];
  for (var d = _dayKey(start);
      d.isBefore(end);
      d = d.add(const Duration(days: 1))) {
    daily.add(DailyRevenue(d, byDay[d] ?? 0));
  }

  return AnalyticsSummary(
    revenue: revenue,
    salesCount: salesCount,
    discount: discount,
    cost: cost,
    stockValue: stockValue,
    expenses: expenses,
    creditSales: creditSales,
    creditOutstanding: creditOutstanding,
    daily: daily,
    topProducts: top.take(topN).toList(),
  );
}

/// How strongly a revenue bar is tinted, by its share of the range's peak.
///
/// A flat single colour made a 5,000-Kyat day and a 175,000-Kyat day look
/// like the same "kind" of day; the fill now scales with the value — a
/// floor of 0.35 keeps quiet days visible (never ghosted out entirely) and
/// the peak always reads at full strength.
double barFillAlpha(double revenue, double peak) {
  if (peak <= 0 || revenue <= 0) return 0.35;
  final ratio = revenue / peak;
  if (ratio >= 1) return 1.0;
  return 0.35 + 0.65 * ratio;
}
