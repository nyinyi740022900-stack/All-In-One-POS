/// One open batch of purchased/adjusted-in stock, oldest first. [id]
/// identifies the underlying `StockLots` row so the caller can persist
/// [consumeFifo]'s result back (update partially-consumed lots, delete
/// exhausted ones). Named distinctly from the Drift-generated `StockLot`
/// row class (for the `StockLots` table) since this is a plain algorithm-
/// level value, not a DB row.
class FifoLot {
  final int id;
  final int remainingQty;
  final int unitCost;

  const FifoLot(
      {required this.id, required this.remainingQty, required this.unitCost});

  @override
  bool operator ==(Object other) =>
      other is FifoLot &&
      other.id == id &&
      other.remainingQty == remainingQty &&
      other.unitCost == unitCost;

  @override
  int get hashCode => Object.hash(id, remainingQty, unitCost);

  @override
  String toString() =>
      'FifoLot(id: $id, remainingQty: $remainingQty, unitCost: $unitCost)';
}

/// Result of consuming a quantity FIFO from a set of lots.
class FifoConsumption {
  /// Total cost of the units matched to a tracked lot.
  final int totalCost;

  /// Lots after consumption, oldest first — exhausted lots (qty reaches 0)
  /// are dropped from this list entirely.
  final List<FifoLot> remainingLots;

  /// Units requested beyond what any lot could cover (the product predates
  /// FIFO tracking, or was oversold). The caller should price this portion
  /// with a fallback (e.g. the product's flat cost price).
  final int shortfall;

  const FifoConsumption(
      {required this.totalCost,
      required this.remainingLots,
      required this.shortfall});
}

/// Consumes [qty] units from [lots] (assumed already ordered oldest-first),
/// splitting the last lot touched if it has more than [qty] needs.
FifoConsumption consumeFifo(List<FifoLot> lots, int qty) {
  if (qty <= 0) {
    return FifoConsumption(totalCost: 0, remainingLots: lots, shortfall: 0);
  }
  var remaining = qty;
  var totalCost = 0;
  final kept = <FifoLot>[];
  for (final lot in lots) {
    if (remaining <= 0) {
      kept.add(lot);
      continue;
    }
    final take = remaining < lot.remainingQty ? remaining : lot.remainingQty;
    totalCost += take * lot.unitCost;
    remaining -= take;
    final left = lot.remainingQty - take;
    if (left > 0) {
      kept.add(FifoLot(id: lot.id, remainingQty: left, unitCost: lot.unitCost));
    }
  }
  return FifoConsumption(
      totalCost: totalCost, remainingLots: kept, shortfall: remaining);
}
