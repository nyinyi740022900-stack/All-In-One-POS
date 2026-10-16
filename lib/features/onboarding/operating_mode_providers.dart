import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../printing/printing_providers.dart';

String localCalendarYmd([DateTime? now]) =>
    DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());

/// Today's local calendar date. The daily gate used to read the date only
/// when first evaluated, so an app left open across midnight (or resumed the
/// next morning) kept yesterday's answer until something else happened to
/// invalidate it. Watching this makes it recompute when the day changes.
///
/// The value is synchronous (no loading state for dependents). It is moved
/// forward by [CalendarDayTicker] in the app shell — a periodic check plus
/// app resume — rather than by a timer owned here, so the timer's lifetime
/// is the app's widget tree and not every container that reads the gate.
final localCalendarDayProvider =
    StateNotifierProvider<LocalCalendarDay, String>(
      (ref) => LocalCalendarDay(),
    );

class LocalCalendarDay extends StateNotifier<String> {
  LocalCalendarDay() : super(localCalendarYmd());

  /// Re-reads the clock; notifies only when the date actually changed.
  void refresh() {
    final today = localCalendarYmd();
    if (today != state) state = today;
  }
}

/// Whether the daily entry gate still needs to run for the active shop.
/// Universal — every shop, regardless of plan or connectivity, confirms
/// identity/branch/cash-open once per local calendar day (identity is
/// confirmed locally via staff PIN when there's no live account session,
/// see `DailyGate`).
///
/// A failed settings read retries, then resolves to **true** (fail-closed:
/// show the gate) rather than skipping identity confirm. Leaving this
/// provider in error holds the whole app on an infinite "checking your shop"
/// spinner (`app.dart`), so we still never surface the error state.
final dailyGateNeededProvider = FutureProvider<bool>((ref) async {
  final shopId = ref.watch(shopIdProvider);
  // Recompute when the local date rolls over, not only on invalidation.
  ref.watch(localCalendarDayProvider);
  if (shopId.isEmpty) return true;
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final ymd = await ref
          .watch(settingsRepositoryProvider)
          .dailyGateYmd(shopId);
      return ymd != localCalendarYmd();
    } catch (e) {
      lastError = e;
      if (attempt < 2) {
        await Future<void>.delayed(
            Duration(milliseconds: 150 * (attempt + 1)));
      }
    }
  }
  // Fail closed: require the gate rather than skipping identity confirm.
  // Returning false here used to let the Sell shell open unsigned when
  // settings were briefly locked. Retry above avoids the spinner-death
  // of leaving this provider in error.
  assert(lastError != null);
  return true;
});
