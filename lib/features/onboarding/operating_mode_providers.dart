import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/repositories/settings_repository.dart';
import '../printing/printing_providers.dart';

/// Device-global Online/Offline shell. Null until first choice / migrate.
final operatingModeProvider = FutureProvider<String?>((ref) {
  return ref.watch(settingsRepositoryProvider).operatingMode();
});

final operatingModeConfirmedProvider = FutureProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).operatingModeConfirmed();
});

/// True when this install locked Online mode. False for Offline or unset.
final isOnlineModeProvider = Provider<bool>((ref) {
  return ref.watch(operatingModeProvider).valueOrNull ==
      SettingsRepository.operatingModeOnline;
});

final isOfflineModeProvider = Provider<bool>((ref) {
  return ref.watch(operatingModeProvider).valueOrNull ==
      SettingsRepository.operatingModeOffline;
});

String localCalendarYmd([DateTime? now]) =>
    DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());

/// Whether the daily entry gate still needs to run for the active shop.
/// Universal — every shop, regardless of plan or connectivity, confirms
/// identity/branch/cash-open once per local calendar day (identity is
/// confirmed locally via staff PIN when there's no live account session,
/// see `DailyGate`).
final dailyGateNeededProvider = FutureProvider<bool>((ref) async {
  final shopId = ref.watch(shopIdProvider);
  if (shopId.isEmpty) return false;
  final ymd = await ref
      .watch(settingsRepositoryProvider)
      .dailyGateYmd(shopId);
  return ymd != localCalendarYmd();
});
