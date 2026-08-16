import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/sync/sync_providers.dart';
import 'package:mm_pos/features/license/license_model.dart';

void main() {
  ShopDevice device({
    required String deviceId,
    required DateTime createdAt,
    bool realtimeEnabled = true,
    bool bound = true,
  }) {
    return ShopDevice(
      key: 'K-$deviceId',
      deviceId: bound ? deviceId : null,
      status: 'active',
      lastVerifiedAt: null,
      createdAt: createdAt,
      realtimeEnabled: realtimeEnabled,
    );
  }

  group('realtimePriorityRank', () {
    test('the earliest-bound realtime-enabled device ranks 1', () {
      final devices = [
        device(deviceId: 'b', createdAt: DateTime(2026, 1, 2)),
        device(deviceId: 'a', createdAt: DateTime(2026, 1, 1)),
        device(deviceId: 'c', createdAt: DateTime(2026, 1, 3)),
      ];
      expect(realtimePriorityRank(devices, 'a'), 1);
      expect(realtimePriorityRank(devices, 'b'), 2);
      expect(realtimePriorityRank(devices, 'c'), 3);
    });

    test('a device with realtime_enabled=false is excluded from ranking '
        'entirely, not just deprioritized', () {
      final devices = [
        device(deviceId: 'a', createdAt: DateTime(2026, 1, 1)),
        device(
          deviceId: 'b',
          createdAt: DateTime(2026, 1, 2),
          realtimeEnabled: false,
        ),
        device(deviceId: 'c', createdAt: DateTime(2026, 1, 3)),
      ];
      expect(realtimePriorityRank(devices, 'a'), 1);
      expect(realtimePriorityRank(devices, 'b'), isNull);
      // c is still rank 2 among the realtime-enabled set, not 3 — b never
      // occupies a slot in the ranking at all.
      expect(realtimePriorityRank(devices, 'c'), 2);
    });

    test('an unbound (released) slot is excluded even if realtime_enabled',
        () {
      final devices = [
        device(deviceId: 'a', createdAt: DateTime(2026, 1, 1), bound: false),
        device(deviceId: 'b', createdAt: DateTime(2026, 1, 2)),
      ];
      expect(realtimePriorityRank(devices, 'a'), isNull);
      expect(realtimePriorityRank(devices, 'b'), 1);
    });

    test('returns null for a device not present in the list at all', () {
      final devices = [device(deviceId: 'a', createdAt: DateTime(2026, 1, 1))];
      expect(realtimePriorityRank(devices, 'not-in-list'), isNull);
    });

    test('an empty device list ranks nothing', () {
      expect(realtimePriorityRank(const [], 'a'), isNull);
    });
  });
}
