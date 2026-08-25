import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/license/license_expiry_watcher.dart';
import 'package:mm_pos/features/license/license_status.dart';

/// The rule that decides whether to nag a shop about its licence running
/// out. Pure, so every branch is pinned here rather than argued about — and
/// the failure modes are asymmetric: warning too often trains the owner to
/// dismiss the alert, warning too late costs them Premium mid-trading-day.
void main() {
  final now = DateTime(2026, 8, 25, 14, 30);
  ExpiryReminder? at(
    DateTime expiresAt, {
    LicensePlan plan = LicensePlan.monthly,
    String? lastWarned,
  }) =>
      computeExpiryReminder(
        expiresAt: expiresAt,
        now: now,
        plan: plan,
        lastWarned: lastWarned,
      );

  group('wholeDaysUntil counts calendar days, not elapsed hours', () {
    test('expiring late tonight is 0 days left, not 1', () {
      expect(wholeDaysUntil(DateTime(2026, 8, 25, 23, 59), now), 0);
    });
    test('expiring early tomorrow is 1 day left, not 0', () {
      expect(wholeDaysUntil(DateTime(2026, 8, 26, 0, 1), now), 1);
    });
    test('already past is negative', () {
      expect(wholeDaysUntil(DateTime(2026, 8, 24, 23, 59), now), -1);
    });
  });

  group('when a reminder is due', () {
    test('nothing fires while the expiry is comfortably away', () {
      expect(at(DateTime(2026, 9, 30)), isNull);
    });

    test('fires at exactly a week out', () {
      expect(at(DateTime(2026, 9, 1))?.daysLeft, 7);
    });

    test('fires on the last day', () {
      expect(at(DateTime(2026, 8, 25, 23, 0))?.daysLeft, 0);
    });

    test('stays silent once already lapsed — the banner covers that', () {
      expect(at(DateTime(2026, 8, 24)), isNull);
    });

    test('never fires for Free, which has no expiry to miss', () {
      expect(at(DateTime(2026, 9, 1), plan: LicensePlan.free), isNull);
    });

    test('a null expiry is not a reminder', () {
      expect(
        computeExpiryReminder(
          expiresAt: null,
          now: now,
          plan: LicensePlan.monthly,
          lastWarned: null,
        ),
        isNull,
      );
    });
  });

  group('the watermark stops repeats without stopping the next one', () {
    test('the same threshold does not fire twice', () {
      final first = at(DateTime(2026, 9, 1))!;
      expect(at(DateTime(2026, 9, 1), lastWarned: first.stamp), isNull);
    });

    test('a tighter threshold still fires after the looser one was shown', () {
      // Warned at 7 days; four days later only 3 remain and that is a new,
      // more urgent fact the owner has not been told yet.
      final sevenDayStamp = at(DateTime(2026, 9, 1))!.stamp;
      final due = computeExpiryReminder(
        expiresAt: DateTime(2026, 8, 28),
        now: now,
        plan: LicensePlan.monthly,
        lastWarned: sevenDayStamp,
      );
      expect(due?.daysLeft, 3);
    });

    test('renewing invalidates the watermark on its own', () {
      // Stamp carries the old expiry, so after an extension it no longer
      // matches and the next cycle is free to warn again — this is what
      // means no code anywhere has to remember to clear it.
      final oldStamp = at(DateTime(2026, 9, 1))!.stamp;
      final renewed = computeExpiryReminder(
        expiresAt: DateTime(2026, 12, 1),
        now: DateTime(2026, 11, 27),
        plan: LicensePlan.monthly,
        lastWarned: oldStamp,
      );
      expect(renewed?.daysLeft, 4);
    });
  });
}
