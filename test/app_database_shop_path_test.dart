import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';

void main() {
  group('AppDatabase shop path helpers', () {
    test('legacy path stays mm_pos.sqlite', () {
      expect(AppDatabase.kLegacyDbFileName, 'mm_pos.sqlite');
      expect(AppDatabase.legacyDbPath('/docs'), '/docs/mm_pos.sqlite');
      expect(AppDatabase.fileNameForShop(''), AppDatabase.kLegacyDbFileName);
      expect(AppDatabase.usePerShopDbFiles, isFalse);
    });

    test('per-shop filename sanitizes unsafe characters', () {
      expect(AppDatabase.fileNameForShop('shop-abc'), 'mm_pos_shop-abc.sqlite');
      expect(
        AppDatabase.fileNameForShop('shop/../evil id'),
        'mm_pos_shop____evil_id.sqlite',
      );
      expect(
        AppDatabase.pathForShop('/docs', 'shop-1'),
        '/docs/mm_pos_shop-1.sqlite',
      );
    });
  });
}
