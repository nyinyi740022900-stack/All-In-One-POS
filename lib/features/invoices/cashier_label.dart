/// Who rang this sale — named roster member, or Owner when no staff id
/// was stamped (owner mode / shops without a roster).
///
/// Pure so invoice, thermal receipt, and tests share one rule. A deleted
/// staff row falls back to [deviceLabel] then [ownerLabel] rather than a
/// blank cashier line.
String cashierNameForSale({
  required String? staffId,
  required List<({String id, String name})> members,
  required String ownerLabel,
  String? deviceLabel,
}) {
  final id = (staffId ?? '').trim();
  if (id.isNotEmpty) {
    for (final m in members) {
      if (m.id == id) return m.name;
    }
    final device = (deviceLabel ?? '').trim();
    if (device.isNotEmpty) return device;
  }
  return ownerLabel;
}
