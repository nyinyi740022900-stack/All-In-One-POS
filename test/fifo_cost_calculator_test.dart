import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/domain/fifo_cost_calculator.dart';

void main() {
  test('consumes a single lot partially, leaving the remainder', () {
    final lots = [const FifoLot(id: 1, remainingQty: 10, unitCost: 500)];
    final r = consumeFifo(lots, 4);
    expect(r.totalCost, 2000);
    expect(r.shortfall, 0);
    expect(r.remainingLots, [const FifoLot(id: 1, remainingQty: 6, unitCost: 500)]);
  });

  test('drains oldest lot first, then spills into the next', () {
    final lots = [
      const FifoLot(id: 1, remainingQty: 3, unitCost: 500),
      const FifoLot(id: 2, remainingQty: 10, unitCost: 700),
    ];
    final r = consumeFifo(lots, 5);
    // 3 units @ 500 + 2 units @ 700
    expect(r.totalCost, 1500 + 1400);
    expect(r.shortfall, 0);
    expect(r.remainingLots, [const FifoLot(id: 2, remainingQty: 8, unitCost: 700)]);
  });

  test('exhausts a lot exactly, dropping it from the remaining list', () {
    final lots = [const FifoLot(id: 1, remainingQty: 3, unitCost: 500)];
    final r = consumeFifo(lots, 3);
    expect(r.totalCost, 1500);
    expect(r.remainingLots, isEmpty);
    expect(r.shortfall, 0);
  });

  test('reports a shortfall when qty exceeds every lot combined', () {
    final lots = [const FifoLot(id: 1, remainingQty: 2, unitCost: 500)];
    final r = consumeFifo(lots, 5);
    expect(r.totalCost, 1000); // only the 2 tracked units
    expect(r.shortfall, 3);
    expect(r.remainingLots, isEmpty);
  });

  test('no lots at all is a full shortfall', () {
    final r = consumeFifo(const [], 4);
    expect(r.totalCost, 0);
    expect(r.shortfall, 4);
  });

  test('qty <= 0 is a no-op that returns the lots untouched', () {
    final lots = [const FifoLot(id: 1, remainingQty: 10, unitCost: 500)];
    final r = consumeFifo(lots, 0);
    expect(r.totalCost, 0);
    expect(r.remainingLots, lots);
  });

  test('lots beyond what was needed are untouched, not just re-added', () {
    final lots = [
      const FifoLot(id: 1, remainingQty: 2, unitCost: 500),
      const FifoLot(id: 2, remainingQty: 5, unitCost: 600),
    ];
    final r = consumeFifo(lots, 2);
    expect(r.remainingLots, [
      const FifoLot(id: 2, remainingQty: 5, unitCost: 600),
    ]);
  });
}
