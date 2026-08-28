import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../printing/printing_providers.dart';

String localCalendarYmd([DateTime? now]) =>
    DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());

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
