// Rows arriving without an HLC (pre-upgrade writers, storefront inserts)
// get a deterministic fallback derived from the SERVER-stamped `received_at`
// plus the row id ([synthHlc]) — never from a device clock.
import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/database.dart';

/// Hybrid Logical Clock (audit H2 residual): a totally-ordered, causally-
/// sound timestamp that does NOT trust device wall-clock skew for conflict
/// decisions.
///
/// Encoded as `"<wallMs>:<counter>:<deviceId>"` and compared as the tuple
/// (wallMs, counter, deviceId) — see [compareHlc]. Every competing replica
/// evaluating the same pair reaches the SAME verdict, so concurrent offline
/// edits always converge on one winner everywhere (no split-brain), unlike
/// raw `updated_at` comparisons where equal/skewed wall clocks let devices
/// disagree forever.
///
/// Ordering contract in this app: HLCs are minted by the SyncEngine when a
/// row is PUSHED (not at edit time), in outbox sequence — so a device's own
/// edit order is preserved, and cross-device simultaneity resolves to the
/// server's last physical writer, deterministically. Rows arriving without
/// an HLC (pre-upgrade writers, storefront/service-role inserts) get a
/// deterministic fallback derived from the SERVER-stamped `received_at`
/// plus the row id ([synthHlc]) — never from a device clock.

const String _kHlcStateKey = 'sync.hlc.state';

/// Parses `"<wallMs>:<counter>:<deviceId>"`; returns null when malformed.
({int wall, int counter, String device})? tryParseHlc(String? hlc) {
  if (hlc == null) return null;
  final parts = hlc.split(':');
  if (parts.length != 3) return null;
  final wall = int.tryParse(parts[0]);
  final counter = int.tryParse(parts[1]);
  if (wall == null || counter == null || parts[2].isEmpty) return null;
  return (wall: wall, counter: counter, device: parts[2]);
}

/// Total order over HLCs. Malformed/null values sort lowest so legacy rows
/// always lose against anything HLC-bearing.
int compareHlc(String? a, String? b) {
  final pa = tryParseHlc(a);
  final pb = tryParseHlc(b);
  if (pa == null && pb == null) return 0;
  if (pa == null) return -1;
  if (pb == null) return 1;
  if (pa.wall != pb.wall) return pa.wall.compareTo(pb.wall);
  if (pa.counter != pb.counter) return pa.counter.compareTo(pb.counter);
  return pa.device.compareTo(pb.device);
}

/// Deterministic stand-in for rows that were written without an HLC:
/// derived from the SERVER-stamped stamp (received_at preferred, falling
/// back to updated_at) so every replica computes the identical value.
String synthHlc(DateTime serverStampUtc, String rowId) {
  final wall =
      serverStampUtc.toUtc().millisecondsSinceEpoch;
  final idHash = rowId.hashCode & 0xFFFF;
  return '$wall:0:id-$idHash';
}

/// Best-known HLC for [m] (a remote row map): its explicit hlc column, or
/// the deterministic received_at/updated_at fallback.
String hlcOfRemoteRow(Map<String, dynamic> m) {
  final explicit = m['hlc'] as String?;
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final stamp = (m['received_at'] ?? m['updated_at']) as String?;
  final parsed = stamp == null ? null : DateTime.tryParse(stamp);
  return synthHlc(parsed?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0),
      m['id'] as String? ?? '');
}

Future<({int wall, int counter})> _loadState(AppDatabase db) async {
  final row = await (db.select(db.appSettings)
        ..where((s) => s.key.equals(_kHlcStateKey)))
      .getSingleOrNull();
  if (row == null) return (wall: 0, counter: 0);
  try {
    final m = jsonDecode(row.value) as Map<String, dynamic>;
    return (wall: m['w'] as int? ?? 0, counter: m['c'] as int? ?? 0);
  } catch (_) {
    return (wall: 0, counter: 0);
  }
}

Future<void> _saveState(AppDatabase db, int wall, int counter) {
  return db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(
          key: const Value(_kHlcStateKey),
          value: Value(jsonEncode({'w': wall, 'c': counter})),
        ),
      );
}

/// Mints the next HLC for THIS device (monotonic: never below the previous
/// mint, never below anything previously received — [receiveHlc] handles
/// the latter).
Future<String> mintHlc(AppDatabase db, String deviceId,
    {DateTime? now}) async {
  final state = await _loadState(db);
  final wall = (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch;
  final newWall = wall > state.wall ? wall : state.wall;
  final newCounter = newWall > state.wall ? 0 : state.counter + 1;
  await _saveState(db, newWall, newCounter);
  return '$newWall:$newCounter:$deviceId';
}

/// Advances the clock past an observed foreign HLC (Lamport receive rule):
/// subsequent mints on this device are guaranteed to sort after everything
/// this device has ever seen, keeping causality across offline stretches.
Future<void> receiveHlc(AppDatabase db, String? incoming) async {
  final p = tryParseHlc(incoming);
  if (p == null) return;
  final state = await _loadState(db);
  final newWall = p.wall > state.wall ? p.wall : state.wall;
  final newCounter =
      p.wall >= state.wall ? (p.counter > state.counter ? p.counter : state.counter) : state.counter;
  // +1 headroom so the NEXT mint strictly exceeds everything observed.
  await _saveState(db, newWall, newCounter + 1);
}
