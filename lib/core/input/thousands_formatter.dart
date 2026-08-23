import 'package:flutter/services.dart';

/// Groups digits with thousands separators as the user types — "1200000"
/// becomes "1,200,000" live. A cashier counting zeros across a seven-digit
/// kyat total is counting mistakes; the grouped figure is what the paper
/// receipt and the customer's own mental math both show.
///
/// Digits only — pair with [FilteringTextInputFormatter.digitsOnly] *before*
/// this formatter and a [LengthLimitingTextInputFormatter] after it (the
/// length limit counts separators too, so budget for them: 13 chars ≈ 10
/// digits + 3 commas).
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  static const String _sep = ',';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = digitsOf(newValue.text);
    final grouped = formatThousandsText(digits);
    if (grouped == newValue.text) return newValue;

    // Preserve the caret relative to the digits around it, not the raw
    // offset — inserting/removing separators shifts every position after
    // them, and a caret that jumps to the end mid-edit reads as the field
    // fighting back.
    final clamped = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBeforeCaret = digitsOf(newValue.text.substring(0, clamped)).length;
    var offset = 0;
    var seen = 0;
    while (offset < grouped.length && seen < digitsBeforeCaret) {
      if (grouped[offset] != _sep) seen++;
      offset++;
    }
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  /// Strips everything that isn't 0-9.
  static String digitsOf(String s) => s.replaceAll(RegExp('[^0-9]'), '');

  /// "1234567" → "1,234,567". Empty in, empty out.
  static String formatThousandsText(String digits) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buf.write(digits[i]);
      final remaining = digits.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buf.write(_sep);
    }
    return buf.toString();
  }
}

/// The largest amount any money input accepts — 10 digits, matching the
/// checkout keypad's own ceiling. Past this, a field is clamped here rather
/// than silently reading as 0 (audit QA-L3: `int.tryParse` returns null for
/// a >19-digit paste and the old fallback swallowed it into zero).
const int maxMoneyInputKyat = 9999999999;

/// "1,200,000" → 1200000; anything unparsable → 0; absurd digit runs clamp
/// to [maxMoneyInputKyat] instead of wrapping to null→0.
int parseThousands(String s) {
  final digits = ThousandsSeparatorInputFormatter.digitsOf(s);
  final value = int.tryParse(digits);
  if (value == null) return digits.isEmpty ? 0 : maxMoneyInputKyat;
  return value;
}

/// 1200000 → "1,200,000" — for writing a programmatic amount into a
/// formatted field so it displays exactly like user-typed text.
String formatThousands(int value) =>
    value <= 0 ? '' : ThousandsSeparatorInputFormatter.formatThousandsText('$value');
