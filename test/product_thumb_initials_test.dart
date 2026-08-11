import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/widgets/app_widgets.dart';

/// The no-photo fallback on the Sell grid and in the cart is an initials
/// plate, so this string is on screen for most products in a real shop (very
/// few get photographed). Getting it wrong is visible, not silent: slicing a
/// Myanmar name by code unit strands a combining mark and renders a
/// dotted-circle placeholder.
void main() {
  group('ProductThumb.initialsFor', () {
    test('two Latin words give both initials, uppercased', () {
      expect(ProductThumb.initialsFor('Coca Cola'), 'CC');
      expect(ProductThumb.initialsFor('green tea'), 'GT');
    });

    test('a single Latin word gives its first two letters', () {
      expect(ProductThumb.initialsFor('Rice'), 'RI');
      expect(ProductThumb.initialsFor('A'), 'A');
    });

    test('Myanmar gives exactly one whole syllable, never a partial cluster',
        () {
      // Each expectation is one grapheme cluster: base letter plus every
      // medial/vowel sign that hangs off it.
      expect(ProductThumb.initialsFor('ကိုကာကိုလာ (ဗူး)'), 'ကို');
      expect(ProductThumb.initialsFor('ရေသန့် (၁ လီတာ)'), 'ရေ');
      expect(ProductThumb.initialsFor('အုန်းနို့ ဘီစကွတ်'), 'အု');
      // Stacked medials (ျ + ွ + ှ) must stay attached to their base.
      expect(ProductThumb.initialsFor('ရွှေဖီ ကော်ဖီမစ်'), 'ရွှေ');
      expect(ProductThumb.initialsFor('ကျွန်တော်'), 'ကျွ');
    });

    test('a bracketed second word is never used as an initial', () {
      // "R(" would be the naive answer here.
      expect(ProductThumb.initialsFor('Rice (5kg)'), 'RI');
    });

    test('empty and whitespace-only names produce no initials', () {
      expect(ProductThumb.initialsFor(''), '');
      expect(ProductThumb.initialsFor('   '), '');
    });
  });
}
