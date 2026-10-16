/// Whether the daily gate can skip "who is opening + PIN" and go straight
/// to branch / opening amount.
///
/// An invited staff account already IS the identity: its sales are stamped
/// with its own linked roster profile (`saleCashierIdProvider`), so it is
/// never asked to pick Owner or another cashier — offering those only let
/// someone ring sales up under another person's name.
///
/// Otherwise a shop with a named staff roster must pick Owner or a named
/// person — even if an owner email session is signed in — because one phone
/// can be handed between people, and the cashier line on invoices should be
/// chosen on purpose. Skip only when the roster is empty *and* this device
/// is not already locked in staff mode.
bool shouldSkipDailyGateIdentity({
  required bool rosterEmpty,
  required bool signedIn,
  required bool localRoleLoaded,
  required String localRole,
  bool invitedStaffAccount = false,
}) {
  if (signedIn && invitedStaffAccount) return true;
  if (!rosterEmpty) return false;
  if (signedIn) return true;
  return localRoleLoaded && localRole != 'staff';
}
