import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/analytics/analytics_calculator.dart';

void main() {
  final d1 = DateTime(2026, 7, 8, 10);
  final d2 = DateTime(2026, 7, 9, 15);
  final start = DateTime(2026, 7, 8);
  final end = DateTime(2026, 7, 11); // 3-day window (8,9,10)

  // A fully-paid cash sale by default; override for credit cases.
  SaleRow sale(int total,
          {String id = 'sale',
          int? paid,
          String method = 'cash',
          int discount = 0,
          DateTime? at,
          bool isRefund = false,
          String? staffId}) =>
      (
        id: id,
        total: total,
        paid: paid ?? total,
        paymentMethod: method,
        discount: discount,
        finalizedAt: at ?? d1,
        isRefund: isRefund,
        staffId: staffId,
      );

  test('aggregates revenue, sales count and discount', () {
    final s = computeAnalytics(
      sales: [
        sale(1000, discount: 100, at: d1),
        sale(500, at: d2),
      ],
      items: const [],
      productCost: const {},
      stockValue: 0,
      start: start,
      end: end,
    );
    expect(s.revenue, 1500);
    expect(s.salesCount, 2);
    expect(s.discount, 100);
  });

  test('profit = revenue - cost of goods sold (flat cost fallback)', () {
    final s = computeAnalytics(
      sales: [sale(2100, at: d1)],
      items: [
        (
          saleId: '',
          productId: 'p1',
          name: 'Coke',
          qty: 3,
          lineTotal: 2100,
          costSnapshot: null,
        ),
      ],
      productCost: {'p1': 550},
      stockValue: 0,
      start: start,
      end: end,
    );
    expect(s.cost, 1650); // 3 * 550
    expect(s.profit, 450); // 2100 - 1650
  });

  test('costSnapshot (FIFO) overrides the flat productCost fallback', () {
    final s = computeAnalytics(
      sales: [sale(2100, at: d1)],
      items: [
        // Bought this batch at 600/unit, not the product's current 550.
        (
          saleId: '',
          productId: 'p1',
          name: 'Coke',
          qty: 3,
          lineTotal: 2100,
          costSnapshot: 1800,
        ),
      ],
      productCost: {'p1': 550},
      stockValue: 0,
      start: start,
      end: end,
    );
    expect(s.cost, 1800); // FIFO snapshot, not 3 * 550
    expect(s.profit, 300); // 2100 - 1800
  });

  test('daily series is zero-filled across the whole range', () {
    final s = computeAnalytics(
      sales: [
        sale(300, at: d1),
        sale(700, at: d1),
      ],
      items: const [],
      productCost: const {},
      stockValue: 0,
      start: start,
      end: end,
    );
    expect(s.daily.length, 3);
    expect(s.daily[0].revenue, 1000); // both on day 1
    expect(s.daily[1].revenue, 0);
    expect(s.daily[2].revenue, 0);
  });

  test('top products ranked by revenue', () {
    final s = computeAnalytics(
      sales: const [],
      items: [
        (saleId: '', productId: 'a', name: 'A', qty: 1, lineTotal: 100, costSnapshot: null),
        (saleId: '', productId: 'b', name: 'B', qty: 5, lineTotal: 900, costSnapshot: null),
        (saleId: '', productId: 'a', name: 'A', qty: 2, lineTotal: 200, costSnapshot: null),
      ],
      productCost: const {},
      stockValue: 0,
      start: start,
      end: end,
    );
    expect(s.topProducts.first.productId, 'b');
    expect(s.topProducts.first.revenue, 900);
    final a = s.topProducts.firstWhere((t) => t.productId == 'a');
    expect(a.qty, 3); // merged 1 + 2
    expect(a.revenue, 300);
  });

  test('top products allocate order-level discount across lines', () {
    final s = computeAnalytics(
      sales: [sale(800, id: 's1', discount: 200)],
      items: [
        (
          saleId: 's1',
          productId: 'a',
          name: 'A',
          qty: 1,
          lineTotal: 400,
          costSnapshot: null,
        ),
        (
          saleId: 's1',
          productId: 'b',
          name: 'B',
          qty: 1,
          lineTotal: 600,
          costSnapshot: null,
        ),
      ],
      productCost: const {},
      stockValue: 0,
      start: start,
      end: end,
    );
    // subtotal 1000, total 800 → A 320, B 480
    expect(s.topProducts.firstWhere((t) => t.productId == 'a').revenue, 320);
    expect(s.topProducts.firstWhere((t) => t.productId == 'b').revenue, 480);
  });

  test('stock value is passed through', () {
    final s = computeAnalytics(
      sales: const [],
      items: const [],
      productCost: const {},
      stockValue: 42000,
      start: start,
      end: end,
    );
    expect(s.stockValue, 42000);
  });

  test('credit metrics: any sale with total > paid counts as outstanding', () {
    final s = computeAnalytics(
      sales: [
        sale(1000, at: d1), // fully paid → not credit
        sale(5000, paid: 2000, method: 'cash', at: d1), // 3000 owed (partial cash)
        sale(3000, paid: 3000, method: 'credit', at: d2), // fully paid → settled
      ],
      items: const [],
      productCost: const {},
      stockValue: 0,
      start: start,
      end: end,
    );
    expect(s.revenue, 9000); // full billed amount (accrual)
    expect(s.creditSales, 1); // only the one still owing
    expect(s.creditOutstanding, 3000); // 5000 − 2000
    expect(s.collected, 6000); // 9000 − 3000
  });

  test('netProfit = gross profit - expenses, expenses defaults to 0', () {
    final noExpenses = computeAnalytics(
      sales: [sale(2100, at: d1)],
      items: [
        (saleId: '', productId: 'p1', name: 'Coke', qty: 3, lineTotal: 2100, costSnapshot: 1800),
      ],
      productCost: const {},
      stockValue: 0,
      start: start,
      end: end,
    );
    expect(noExpenses.profit, 300);
    expect(noExpenses.expenses, 0);
    expect(noExpenses.netProfit, 300); // unaffected when nothing passed in

    final withExpenses = computeAnalytics(
      sales: [sale(2100, at: d1)],
      items: [
        (saleId: '', productId: 'p1', name: 'Coke', qty: 3, lineTotal: 2100, costSnapshot: 1800),
      ],
      productCost: const {},
      stockValue: 0,
      start: start,
      end: end,
      expenses: 200,
    );
    expect(withExpenses.profit, 300); // gross profit untouched by expenses
    expect(withExpenses.netProfit, 100); // 300 - 200
  });

  test('a refund row nets out revenue but is excluded from salesCount', () {
    final s = computeAnalytics(
      sales: [
        sale(2100, at: d1),
        sale(-2100, paid: -2100, at: d1, isRefund: true),
      ],
      items: const [],
      productCost: const {},
      stockValue: 0,
      start: start,
      end: end,
    );
    expect(s.revenue, 0); // fully netted out
    expect(s.salesCount, 1); // the refund row itself isn't counted as a sale
  });

  group('salesByStaff', () {
    test('groups revenue and count per staffId, sorted by revenue desc', () {
      final s = computeAnalytics(
        sales: [
          sale(1000, at: d1, staffId: 'staff-a'),
          sale(500, at: d1, staffId: 'staff-a'),
          sale(3000, at: d1, staffId: 'staff-b'),
        ],
        items: const [],
        productCost: const {},
        stockValue: 0,
        start: start,
        end: end,
      );
      expect(s.salesByStaff, hasLength(2));
      expect(s.salesByStaff[0].staffId, 'staff-b');
      expect(s.salesByStaff[0].revenue, 3000);
      expect(s.salesByStaff[0].salesCount, 1);
      expect(s.salesByStaff[1].staffId, 'staff-a');
      expect(s.salesByStaff[1].revenue, 1500);
      expect(s.salesByStaff[1].salesCount, 2);
    });

    test('a null/blank staffId groups as one "unattributed" (owner) bucket',
        () {
      final s = computeAnalytics(
        sales: [
          sale(1000, at: d1, staffId: null),
          sale(500, at: d1, staffId: ''),
        ],
        items: const [],
        productCost: const {},
        stockValue: 0,
        start: start,
        end: end,
      );
      expect(s.salesByStaff, hasLength(1));
      expect(s.salesByStaff.single.staffId, isNull);
      expect(s.salesByStaff.single.revenue, 1500);
      expect(s.salesByStaff.single.salesCount, 2);
    });

    test('a refund nets revenue for its staffId but is excluded from that '
        "staff's salesCount", () {
      final s = computeAnalytics(
        sales: [
          sale(2100, at: d1, staffId: 'staff-a'),
          sale(-2100, paid: -2100, at: d1, isRefund: true, staffId: 'staff-a'),
        ],
        items: const [],
        productCost: const {},
        stockValue: 0,
        start: start,
        end: end,
      );
      expect(s.salesByStaff.single.staffId, 'staff-a');
      expect(s.salesByStaff.single.revenue, 0);
      expect(s.salesByStaff.single.salesCount, 1);
    });
  });

  test('creditOutstanding/collected respect FIFO repayment allocation '
      '(regression: a fully-repaid credit sale kept showing as outstanding '
      'in Analytics while the Credit book correctly showed 0)', () {
    final s = computeAnalytics(
      sales: [
        sale(1900, paid: 0, method: 'credit', id: 'c1', at: d1),
        sale(1000, at: d2),
      ],
      items: const [],
      productCost: const {},
      stockValue: 0,
      start: DateTime(2026, 7, 1),
      end: DateTime(2026, 8, 1),
    );
    // Without the allocation map, raw LWW behaviour applies.
    expect(s.creditOutstanding, 1900);
    expect(s.collected, 1000);

    // Fully repaid via the Credit book → no longer outstanding, money
    // counts as collected (matches what the Credit book shows).
    final repaid = computeAnalytics(
      sales: [
        sale(1900, paid: 0, method: 'credit', id: 'c1', at: d1),
        sale(1000, at: d2),
      ],
      items: const [],
      productCost: const {},
      stockValue: 0,
      start: DateTime(2026, 7, 1),
      end: DateTime(2026, 8, 1),
      creditOwedBySaleId: const {'c1': 0},
    );
    expect(repaid.creditOutstanding, 0);
    expect(repaid.collected, 2900);

    // Partially repaid (500 of 1900) → only the remainder is outstanding.
    final partial = computeAnalytics(
      sales: [
        sale(1900, paid: 0, method: 'credit', id: 'c1', at: d1),
        sale(1000, at: d2),
      ],
      items: const [],
      productCost: const {},
      stockValue: 0,
      start: DateTime(2026, 7, 1),
      end: DateTime(2026, 8, 1),
      creditOwedBySaleId: const {'c1': 1400},
    );
    expect(partial.creditOutstanding, 1400);
    // revenue(2900) − remaining outstanding(1400): the 500 repaid counts as
    // collected because the full billed amount is in revenue.
    expect(partial.collected, 1500);
  });

  group('barFillAlpha (volume-tinted revenue bars)', () {
    test('peak reads at full strength, quiet days stay visible', () {
      expect(barFillAlpha(175000, 175000), 1.0);
      expect(barFillAlpha(5000, 175000), closeTo(0.35 + 0.65 * 5000 / 175000, 1e-9));
    });

    test('empty range and zero bars take the visibility floor', () {
      expect(barFillAlpha(0, 0), 0.35);
      expect(barFillAlpha(0, 175000), 0.35);
    });
  });
}
