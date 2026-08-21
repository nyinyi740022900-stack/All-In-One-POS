import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/onboarding/daily_gate_logic.dart';

void main() {
  test('roster present never skips identity, even when signed in', () {
    expect(
      shouldSkipDailyGateIdentity(
        rosterEmpty: false,
        signedIn: true,
        localRoleLoaded: true,
        localRole: 'owner',
      ),
      isFalse,
    );
  });

  test('empty roster + signed in skips identity', () {
    expect(
      shouldSkipDailyGateIdentity(
        rosterEmpty: true,
        signedIn: true,
        localRoleLoaded: true,
        localRole: 'owner',
      ),
      isTrue,
    );
  });

  test('empty roster + unsigned owner skips identity', () {
    expect(
      shouldSkipDailyGateIdentity(
        rosterEmpty: true,
        signedIn: false,
        localRoleLoaded: true,
        localRole: 'owner',
      ),
      isTrue,
    );
  });

  test('empty roster + local staff mode still asks identity', () {
    expect(
      shouldSkipDailyGateIdentity(
        rosterEmpty: true,
        signedIn: false,
        localRoleLoaded: true,
        localRole: 'staff',
      ),
      isFalse,
    );
  });
}
