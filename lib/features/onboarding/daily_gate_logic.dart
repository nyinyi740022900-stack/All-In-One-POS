/// Whether the daily gate can skip "who is opening + PIN" and go straight
/// to branch / opening amount.
///
/// A shop with a named staff roster must always pick Owner or a named
/// person — even if an email session is already signed in — so the till
/// identity (and the cashier line on invoices) is chosen on purpose.
/// Skip only when the roster is empty *and* this device is not already
/// locked in staff mode.
bool shouldSkipDailyGateIdentity({
  required bool rosterEmpty,
  required bool signedIn,
  required bool localRoleLoaded,
  required String localRole,
}) {
  if (!rosterEmpty) return false;
  if (signedIn) return true;
  return localRoleLoaded && localRole != 'staff';
}
