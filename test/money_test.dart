import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/currency_def.dart';
import 'package:mm_pos/core/input/thousands_formatter.dart';
import 'package:mm_pos/core/money.dart';

void main() {
  group('Money.formatted', () {
    test('exponent 0 (MMK/JPY) — unchanged whole-unit grouping', () {
      expect(const Money(1250).formatted(), '1,250');
      expect(const Money(1250).formatted(exponent: 0), '1,250');
    });

    test('exponent 2 (THB/USD) — decimal point inserted', () {
      expect(const Money(1250).formatted(exponent: 2), '12.50');
      expect(const Money(5).formatted(exponent: 2), '0.05');
      expect(const Money(100000).formatted(exponent: 2), '1,000.00');
    });

    test('negative amounts', () {
      expect(const Money(-1250).formatted(exponent: 2), '-12.50');
      expect(const Money(-1250).formatted(), '-1,250');
    });
  });

  group('Money.withSymbol / withCurrency', () {
    test('withSymbol threads the exponent through', () {
      expect(const Money(1250).withSymbol('Ks'), '1,250 Ks');
      expect(const Money(1250).withSymbol('฿', exponent: 2), '12.50 ฿');
    });

    test('withCurrency: MMK label is locale-aware, others are not', () {
      expect(const Money(1250).withCurrency(CurrencyDef.mmk, 'en'), '1,250 Ks');
      expect(
          const Money(1250).withCurrency(CurrencyDef.mmk, 'my'), '1,250 ကျပ်');
      expect(
          const Money(1250).withCurrency(CurrencyDef.thb, 'my'), '12.50 ฿');
      expect(
          const Money(1250).withCurrency(CurrencyDef.thb, 'en'), '12.50 ฿');
      expect(const Money(1250).withCurrency(CurrencyDef.usd, 'en'), r'12.50 $');
      expect(const Money(1250).withCurrency(CurrencyDef.jpy, 'en'), '1,250 ¥');
    });
  });

  group('formatMinorUnits (standalone, for the PDF/report formatters)', () {
    test('matches Money.formatted for the same value/exponent', () {
      expect(formatMinorUnits(1250), const Money(1250).formatted());
      expect(formatMinorUnits(1250, exponent: 2),
          const Money(1250).formatted(exponent: 2));
    });
  });

  group('Money.fromString', () {
    test('parses messy input, clamps overlong digit runs', () {
      expect(Money.fromString('1,250 Ks').minor, 1250);
      expect(Money.fromString('9' * 25).minor, maxMoneyInputKyat);
      expect(Money.fromString('-${'9' * 25}').minor, -maxMoneyInputKyat);
    });
  });

  group('parseDecimalMinorUnits / formatDecimalMinorUnits', () {
    test('exponent 0 matches parseThousands/formatThousands exactly', () {
      expect(parseDecimalMinorUnits('1,250', exponent: 0), 1250);
      expect(parseDecimalMinorUnits('1,250', exponent: 0),
          parseThousands('1,250'));
      expect(formatDecimalMinorUnits(1250, exponent: 0), '1,250');
      expect(formatDecimalMinorUnits(1250, exponent: 0),
          formatThousands(1250));
    });

    test('exponent 2 round-trips a decimal amount', () {
      expect(parseDecimalMinorUnits('1,234.56', exponent: 2), 123456);
      expect(formatDecimalMinorUnits(123456, exponent: 2), '1,234.56');
      expect(parseDecimalMinorUnits('0.05', exponent: 2), 5);
      expect(formatDecimalMinorUnits(5, exponent: 2), '0.05');
    });

    test('exponent 2: fewer fractional digits than the exponent pad with '
        'zeros; more get truncated', () {
      expect(parseDecimalMinorUnits('12.5', exponent: 2), 1250);
      expect(parseDecimalMinorUnits('12.567', exponent: 2), 1256);
    });

    test('garbage/empty input parses to 0, never throws', () {
      expect(parseDecimalMinorUnits('', exponent: 2), 0);
      expect(parseDecimalMinorUnits('.', exponent: 2), 0);
      expect(parseDecimalMinorUnits('abc', exponent: 2), 0);
    });

    test('an absurd digit run clamps to maxMoneyInputKyat, not 0', () {
      expect(parseDecimalMinorUnits('9' * 25, exponent: 2), maxMoneyInputKyat);
      expect(parseDecimalMinorUnits('${'9' * 25}.99', exponent: 2),
          maxMoneyInputKyat);
    });

    test('a 17-18 digit whole part clamps rather than silently overflowing '
        'into a negative number (audit: whole * scale used to wrap Dart\'s '
        '64-bit int)', () {
      expect(
        parseDecimalMinorUnits('99999999999999999.99', exponent: 2),
        maxMoneyInputKyat,
      );
      expect(
        parseDecimalMinorUnits('123456789012345678', exponent: 2),
        maxMoneyInputKyat,
      );
      // Never negative for any digit run, regardless of length.
      for (final digits in ['9' * 15, '9' * 17, '9' * 19, '9' * 25]) {
        expect(parseDecimalMinorUnits(digits, exponent: 2),
            greaterThanOrEqualTo(0));
      }
    });

    test('non-positive amounts format to an empty string (clears the field)',
        () {
      expect(formatDecimalMinorUnits(0, exponent: 2), '');
      expect(formatDecimalMinorUnits(-500, exponent: 2), '');
      expect(formatDecimalMinorUnits(0, exponent: 0), '');
    });
  });

  group('DecimalMoneyInputFormatter', () {
    TextEditingValue apply(int exponent, String text) =>
        DecimalMoneyInputFormatter(exponent: exponent).formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
        );

    test('exponent 0 groups digits only, no decimal point allowed', () {
      expect(apply(0, '1200000').text, '1,200,000');
      expect(apply(0, '12.34').text, '1,234');
    });

    test('exponent 2 allows one decimal point and groups the whole part', () {
      expect(apply(2, '1234.5').text, '1,234.5');
      expect(apply(2, '1234.567').text, '1,234.56');
    });

    test('exponent 2: a second "." is dropped, not inserted again', () {
      expect(apply(2, '12.3.4').text, '12.34');
    });
  });

  group('CurrencyDef.byCode', () {
    test('resolves known codes', () {
      expect(CurrencyDef.byCode('THB'), CurrencyDef.thb);
      expect(CurrencyDef.byCode('USD'), CurrencyDef.usd);
      expect(CurrencyDef.byCode('JPY'), CurrencyDef.jpy);
      expect(CurrencyDef.byCode('MMK'), CurrencyDef.mmk);
    });

    test('fails closed to MMK for unknown/null/empty — never blank, never '
        'throws in the sell path', () {
      expect(CurrencyDef.byCode(null), CurrencyDef.mmk);
      expect(CurrencyDef.byCode(''), CurrencyDef.mmk);
      expect(CurrencyDef.byCode('XYZ'), CurrencyDef.mmk);
    });
  });
}
