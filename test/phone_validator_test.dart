import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/phone_validator.dart';

void main() {
  group('looksLikeMyanmarPhone', () {
    test('empty is always fine (phone is optional everywhere)', () {
      expect(looksLikeMyanmarPhone(''), isTrue);
      expect(looksLikeMyanmarPhone('   '), isTrue);
    });

    test('accepts local 09-prefixed numbers, old and new length', () {
      expect(looksLikeMyanmarPhone('091234567'), isTrue); // 7 digits after 09
      expect(looksLikeMyanmarPhone('09123456789'), isTrue); // 9 digits after 09
    });

    test('accepts spaces/hyphens in an otherwise-valid number', () {
      expect(looksLikeMyanmarPhone('09-123-456-789'), isTrue);
      expect(looksLikeMyanmarPhone('09 123 456 789'), isTrue);
    });

    test('accepts international +959/959 format', () {
      expect(looksLikeMyanmarPhone('+959123456789'), isTrue);
      expect(looksLikeMyanmarPhone('959123456789'), isTrue);
    });

    test('rejects an obviously wrong format', () {
      expect(looksLikeMyanmarPhone('12345'), isFalse);
      expect(looksLikeMyanmarPhone('0812345678'), isFalse); // not 09-prefixed
      expect(looksLikeMyanmarPhone('091234'), isFalse); // too short
    });
  });
}
