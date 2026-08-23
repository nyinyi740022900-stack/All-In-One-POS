
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// Owner-editable friendly names for the shop's devices (e.g. "Counter A",
/// "Owner's phone") — see the doc comment on `DeviceLabels` in tables.dart
/// for why this has to be synced rather than a local setting.
class DeviceLabelRepository {
  DeviceLabelRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  Stream<List<DeviceLabel>> watchAll() {
    return (_db.select(_db.deviceLabels)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .watch();
  }

  Future<DeviceLabel?> _existingFor(String deviceId) {
    return (_db.select(_db.deviceLabels)
          ..where((t) =>
              t.shopId.equals(_shopId) &
              t.deviceId.equals(deviceId) &
              t.isDeleted.equals(false)))
        .getSingleOrNull();
  }

  Future<String?> labelFor(String deviceId) async {
    return (await _existingFor(deviceId))?.label;
  }

  /// Sets (or renames) this device's own label — one row per device.
  Future<void> setLabel(String deviceId, String label) async {
    final existing = await _existingFor(deviceId);
    final id = existing?.id ?? _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.deviceLabels).insertOnConflictUpdate(
          DeviceLabelsCompanion(
            id: Value(id),
            shopId: Value(_shopId),
            deviceId: Value(deviceId),
            label: Value(label.trim()),
            updatedAt: Value(now),
            dirty: const Value(true),
          ));
      await _db.into(_db.outbox).insert(OutboxCompanion.insert(
            entityTable: 'device_labels',
            rowId: id,
            op: 'upsert',
          ));
    });
  }
}
