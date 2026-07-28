import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../printing/printing_providers.dart';
import 'device_label_repository.dart';

final deviceLabelRepositoryProvider = Provider<DeviceLabelRepository>((ref) {
  return DeviceLabelRepository(
    ref.watch(databaseProvider),
    ref.watch(shopIdProvider),
  );
});

final deviceLabelsProvider = StreamProvider<List<DeviceLabel>>((ref) {
  return ref.watch(deviceLabelRepositoryProvider).watchAll();
});

/// deviceId -> label, for looking up any sale's device attribution.
final deviceLabelMapProvider = Provider<Map<String, String>>((ref) {
  final labels = ref.watch(deviceLabelsProvider).valueOrNull ?? const [];
  return {for (final l in labels) l.deviceId: l.label};
});

/// This device's own label, if it has set one.
final myDeviceLabelProvider = Provider<String?>((ref) {
  final deviceId = ref.watch(deviceIdProvider).valueOrNull;
  if (deviceId == null) return null;
  return ref.watch(deviceLabelMapProvider)[deviceId];
});
