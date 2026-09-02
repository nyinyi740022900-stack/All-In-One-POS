import 'package:flutter_test/flutter_test.dart';

import 'package:mm_pos/core/money.dart';

void main() {
  group('Money', () {
    test('adds and multiplies in integer kyat', () {
      expect((const Money(1000) + const Money(250)).minor, 1250);
      expect((const Money(500) * 3).minor, 1500);
    });

    test('formats with thousands separators', () {
      expect(const Money(1250000).formatted(), '1,250,000');
      expect(const Money(1250).withSymbol('Ks'), '1,250 Ks');
    });

    test('parses from messy strings', () {
      expect(Money.fromString('1,250 Ks').minor, 1250);
    });
  });
}
