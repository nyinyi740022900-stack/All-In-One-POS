import '../../data/local/database.dart';

/// The stable grouping key for a supplier within Accounts Payable: their
/// directory id if linked, otherwise a normalized form of their snapshotted
/// name — same shape as `credit_repository.dart`'s `creditKeyFor`.
String poSupplierKeyFor(String? supplierId, String name) {
  if (supplierId != null && supplierId.isNotEmpty) return 'id:$supplierId';
  return 'name:${name.trim().toLowerCase()}';
}

/// A supplier's outstanding balance, aggregated from received purchase
/// orders minus payments made — Accounts Payable's mirror image of
/// `CreditCustomer` (money owed *by* the shop, not *to* it).
class SupplierBalance {
  final String key;
  final String? supplierId;
  final String name;
  final int billed; // Σ itemsTotal of received POs
  final int paid; // Σ supplierPayments.amount

  const SupplierBalance({
    required this.key,
    this.supplierId,
    required this.name,
    required this.billed,
    required this.paid,
  });

  int get outstanding {
    final o = billed - paid;
    return o < 0 ? 0 : o;
  }
}

/// Pure: folds received POs + supplier payments into a per-supplier
/// balance. By default only suppliers who are still owed money are
/// returned (largest balance first) — same `includeSettled` escape hatch
/// `CreditRepository.aggregate` offers, for reaching payment history after
/// a debt is fully paid off.
List<SupplierBalance> aggregateAccountsPayable(
  List<PurchaseOrder> receivedPOs,
  List<SupplierPayment> payments, {
  bool includeSettled = false,
}) {
  final billed = <String, int>{};
  final paid = <String, int>{};
  final name = <String, String>{};
  final supplierId = <String, String>{};

  for (final po in receivedPOs) {
    final n = po.supplierName.trim();
    if (n.isEmpty) continue;
    final key = poSupplierKeyFor(po.supplierId, n);
    billed[key] = (billed[key] ?? 0) + po.itemsTotal;
    name[key] = n;
    if (po.supplierId != null) supplierId[key] = po.supplierId!;
  }
  for (final p in payments) {
    final n = p.supplierName.trim();
    if (n.isEmpty) continue;
    final key = poSupplierKeyFor(p.supplierId, n);
    paid[key] = (paid[key] ?? 0) + p.amount;
    name.putIfAbsent(key, () => n);
    if (p.supplierId != null) supplierId.putIfAbsent(key, () => p.supplierId!);
  }

  final result = <SupplierBalance>[];
  for (final key in billed.keys) {
    final b = SupplierBalance(
      key: key,
      supplierId: supplierId[key],
      name: name[key] ?? '',
      billed: billed[key] ?? 0,
      paid: paid[key] ?? 0,
    );
    if (includeSettled || b.outstanding > 0) result.add(b);
  }
  result.sort((a, b) => b.outstanding.compareTo(a.outstanding));
  return result;
}
