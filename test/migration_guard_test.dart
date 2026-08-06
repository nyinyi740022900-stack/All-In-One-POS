import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';

void main() {
  group('isDuplicateColumnMigrationError', () {
    test('detects duplicate column name errors', () {
      expect(
        isDuplicateColumnMigrationError(
          Exception('SqliteException(1): duplicate column name: payment_method'),
        ),
        isTrue,
      );
    });

    test('detects already exists phrasing', () {
      expect(
        isDuplicateColumnMigrationError(
          Exception('Error: column "payment_method" already exists'),
        ),
        isTrue,
      );
    });

    test('does not swallow unrelated migration errors', () {
      expect(
        isDuplicateColumnMigrationError(
          Exception('SqliteException(1): no such table: orders'),
        ),
        isFalse,
      );
    });
  });
}
