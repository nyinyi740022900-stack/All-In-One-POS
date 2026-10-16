/// Who rang this sale — named roster member, or Owner when no staff id
/// was stamped (owner mode / shops without a roster).
///
/// Pure so invoice, thermal receipt, and tests share one rule. A deleted
/// staff row falls back to [deviceLabel], then [staffLabel], rather than a
/// blank cashier line. A sale that WAS stamped with a staff id is never
/// labelled Owner just because that id no longer resolves (a removed
/// profile, or an invited staff account with no linked profile — stamped
/// `account:<user id>`, see `saleCashierIdProvider`); [staffLabel] falls back
/// to [ownerLabel] only for callers that do not supply it.
String cashierNameForSale({
  required String? staffId,
  required List<({String id, String name})> members,
  required String ownerLabel,
  String? staffLabel,
  String? deviceLabel,
}) {
  final id = (staffId ?? '').trim();
  if (id.isNotEmpty) {
    for (final m in members) {
      if (m.id == id) return m.name;
    }
    final device = (deviceLabel ?? '').trim();
    if (device.isNotEmpty) return device;
    return staffLabel ?? ownerLabel;
  }
  return ownerLabel;
}
