import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/input/thousands_formatter.dart';

void main() {
  final f = ThousandsSeparatorInputFormatter();

  TextEditingValue edit(String oldText, String newText, {int offset = -1}) {
    return f.formatEditUpdate(
      TextEditingValue(text: oldText),
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: offset < 0 ? newText.length : offset,
        ),
      ),
    );
  }

  group('ThousandsSeparatorInputFormatter', () {
    test('groups digits in threes', () {
      expect(edit('', '1200000').text, '1,200,000');
      expect(edit('', '500').text, '500');
      expect(edit('', '12000').text, '12,000');
    });

    test('empty stays empty', () {
      expect(edit('1,200', '').text, '');
    });

    test('caret lands at the end after appending', () {
      final v = edit('', '125000');
      expect(v.selection.baseOffset, v.text.length);
      expect(v.text, '125,000');
    });

    test('backspacing a separator keeps the caret on the last digit', () {
      // "1,200" with caret at end; user hits backspace → raw new value
      // would be "1,20" (the comma deleted by the field), digits unchanged
      // grouping re-renders as "1,200"? No — deleting the comma leaves 3
      // digits "120", regrouped to "120".
      final v = edit('1,200', '1,20', offset: 4);
      expect(v.text, '120');
      expect(v.selection.baseOffset, 3);
    });

    test('inserting mid-string keeps the caret relative to its digits', () {
      // Caret after "1," (offset 2) typing "2": digits before caret = 1,
      // result "12,000" with caret after the first digit.
      final v = edit('1,000', '21,000', offset: 1);
      expect(v.text, '21,000');
      expect(v.selection.baseOffset, 1);
    });
  });

  group('helpers', () {
    test('parseThousands strips separators', () {
      expect(parseThousands('1,200,000'), 1200000);
      expect(parseThousands(''), 0);
      expect(parseThousands('abc'), 0);
    });

    test('formatThousands groups; zero and negative are empty', () {
      expect(formatThousands(1200000), '1,200,000');
      expect(formatThousands(0), '');
      expect(formatThousands(-5), '');
    });
  });
}
