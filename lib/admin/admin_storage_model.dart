/// Pure parsing/formatting for the admin console's Storage page — the
/// `storage_report` and `photo_orphans` admin actions (migration 0104).
library;

/// "0 B", "512 B", "1.5 KB", "17.0 MB", "2.25 GB" — binary units, since
/// that is what Supabase's own usage page and plan limits use.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

class ShopUsage {
  const ShopUsage({
    required this.shopId,
    required this.rows,
    required this.bytes,
    required this.photos,
    required this.photoBytes,
  });

  final String shopId;
  final int rows;

  /// Row data only, without indexes — ranks shops, under-reads disk.
  final int bytes;
  final int photos;
  final int photoBytes;

  int get totalBytes => bytes + photoBytes;
}

class StorageReport {
  const StorageReport({
    required this.databaseBytes,
    required this.shops,
    required this.unfolderedPhotos,
    required this.unfolderedPhotoBytes,
  });

  factory StorageReport.fromJson(Map<String, dynamic> json) {
    final shops = [
      for (final s in (json['shops'] as List?) ?? const [])
        if (s is Map)
          ShopUsage(
            shopId: '${s['shop_id']}',
            rows: _int(s['rows']),
            bytes: _int(s['bytes']),
            photos: _int(s['photos']),
            photoBytes: _int(s['photo_bytes']),
          ),
    ]..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    return StorageReport(
      databaseBytes: _int(json['database_bytes']),
      shops: shops,
      unfolderedPhotos: _int(json['unfoldered_photos']),
      unfolderedPhotoBytes: _int(json['unfoldered_photo_bytes']),
    );
  }

  /// The whole Postgres database, system catalogs included — the figure the
  /// Supabase plan's database-size limit is measured against.
  final int databaseBytes;
  final List<ShopUsage> shops;

  /// Pre-0088 uploads at the bucket root, which belong to no shop folder.
  final int unfolderedPhotos;
  final int unfolderedPhotoBytes;

  int get photoBytes =>
      shops.fold(unfolderedPhotoBytes, (sum, s) => sum + s.photoBytes);
  int get photos => shops.fold(unfolderedPhotos, (sum, s) => sum + s.photos);
}

/// The nightly photo clean-up's dry run: what it would delete right now.
class OrphanPhotos {
  const OrphanPhotos({
    required this.files,
    required this.bytes,
    required this.names,
  });

  factory OrphanPhotos.fromJson(Map<String, dynamic> json) => OrphanPhotos(
    files: _int(json['files']),
    bytes: _int(json['bytes']),
    names: [for (final n in (json['names'] as List?) ?? const []) '$n'],
  );

  final int files;
  final int bytes;
  final List<String> names;
}
