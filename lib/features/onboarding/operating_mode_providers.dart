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
/// A failed settings read resolves to **false** (fail-open) rather than
//  leaving the provider in error state: `app.dart` holds the whole app on
/// an infinite "checking your shop" spinner while this has no value, so an
/// error here (e.g. the Drift DB still locked by Free-plan setup writes
/// right after onboarding) used to look exactly like a dead "Get started"
/// button — onboarding closed, then nothing ever appeared, and only a full
/// restart recomputed it successfully.
final dailyGateNeededProvider = FutureProvider<bool>((ref) async {
  final shopId = ref.watch(shopIdProvider);
  if (shopId.isEmpty) return false;
  try {
    final ymd = await ref
        .watch(settingsRepositoryProvider)
        .dailyGateYmd(shopId);
    return ymd != localCalendarYmd();
  } catch (_) {
    return false;
  }
});
