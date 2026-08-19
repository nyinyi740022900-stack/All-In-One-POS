import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/sell/cash_tender.dart';

void main() {
  test('empty / zero total yields no chips', () {
    expect(cashTenderSuggestions(0), isEmpty);
    expect(cashTenderSuggestions(-100), isEmpty);
  });

  test('Exact is always first', () {
    final s = cashTenderSuggestions(12500);
    expect(s.first, 12500);
  });

  test('rounds a mid-range total onto 1k / 5k / 10k notes', () {
    expect(
      cashTenderSuggestions(12500),
      [12500, 13000, 15000, 20000],
    );
  });

  test('small tea-shop total offers 500 then 1k then 5k', () {
    expect(
      cashTenderSuggestions(350),
      [350, 500, 1000, 5000],
    );
  });

  test('does not duplicate Exact as a round-up', () {
    final s = cashTenderSuggestions(5000);
    expect(s.first, 5000);
    expect(s.skip(1), everyElement(greaterThan(5000)));
    expect(s.toSet().length, s.length);
  });

  test('total already on the largest note still offers one overpay', () {
    expect(cashTenderSuggestions(20000), [20000, 40000]);
  });

  test('caps at maxChips including Exact', () {
    final s = cashTenderSuggestions(80, maxChips: 3);
    expect(s, [80, 500, 1000]);
  });

  test('maxChips 1 is Exact only', () {
    expect(cashTenderSuggestions(12500, maxChips: 1), [12500]);
  });
}
