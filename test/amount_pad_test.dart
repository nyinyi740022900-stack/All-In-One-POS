import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/sell/amount_pad.dart';

void main() {
  group('appendPadDigits', () {
    test('first digit from zero', () {
      expect(appendPadDigits(0, '1'), 1);
      expect(appendPadDigits(0, '0'), 0);
    });

    test('each digit shifts left by one place', () {
      expect(appendPadDigits(1, '0'), 10);
      expect(appendPadDigits(12, '5'), 125);
      expect(appendPadDigits(1, '0'), 10);
      var v = 0;
      for (final d in ['1', '0', '0', '0', '0']) {
        v = appendPadDigits(v, d);
      }
      expect(v, 10000);
    });

    test('00 shifts left by two places', () {
      expect(appendPadDigits(5, '00'), 500);
    });
  });
}
