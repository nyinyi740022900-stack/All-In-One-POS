import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/admin/admin_storage_model.dart';

void main() {
  test('formatBytes uses binary units with sensible precision', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1536), '1.50 KB');
    expect(formatBytes(17 * 1024 * 1024), '17.0 MB');
    expect(formatBytes(300 * 1024 * 1024), '300 MB');
    expect(formatBytes(2 * 1024 * 1024 * 1024 + 256 * 1024 * 1024), '2.25 GB');
  });

  test('the report sorts shops by total cost and sums every photo', () {
    final r = StorageReport.fromJson({
      'database_bytes': 17825792,
      'shops': [
        {'shop_id': 'small', 'rows': 3, 'bytes': 100, 'photos': 0},
        {
          'shop_id': 'photos',
          'rows': 1,
          'bytes': 10,
          'photos': 2,
          'photo_bytes': 5000,
        },
        // Postgres bigint can arrive as a string through JSON.
        {'shop_id': 'rows', 'rows': '900', 'bytes': '2000'},
      ],
      'unfoldered_photos': 28,
      'unfoldered_photo_bytes': 700,
    });
    expect(r.shops.map((s) => s.shopId), ['photos', 'rows', 'small']);
    expect(r.shops[1].rows, 900);
    expect(r.photos, 30);
    expect(r.photoBytes, 5700);
    expect(r.databaseBytes, 17825792);
  });

  test('a missing or empty report reads as zero, not a crash', () {
    final r = StorageReport.fromJson(const {});
    expect(r.shops, isEmpty);
    expect(r.photos, 0);
    expect(r.databaseBytes, 0);
    final o = OrphanPhotos.fromJson(const {});
    expect(o.files, 0);
    expect(o.names, isEmpty);
  });

  test('the dry run keeps the server\'s names and totals', () {
    final o = OrphanPhotos.fromJson({
      'ok': true,
      'dry_run': true,
      'files': 2,
      'bytes': 1200,
      'names': ['a/p-1.jpg', 'p-2.jpg'],
    });
    expect(o.files, 2);
    expect(o.bytes, 1200);
    expect(o.names, ['a/p-1.jpg', 'p-2.jpg']);
  });
}
