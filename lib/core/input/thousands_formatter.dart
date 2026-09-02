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

/// Strips everything but digits and (at most) the first '.'.
String _rawDecimalOf(String s) {
  final buf = StringBuffer();
  var seenDot = false;
  for (final ch in s.split('')) {
    if (ch == '.' && !seenDot) {
      buf.write('.');
      seenDot = true;
    } else if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
      buf.write(ch);
    }
  }
  return buf.toString();
}

int _decimalPow10(int exponent) {
  var v = 1;
  for (var i = 0; i < exponent; i++) {
    v *= 10;
  }
  return v;
}

/// The exponent-aware sibling of [ThousandsSeparatorInputFormatter] — for
/// exponent 0 (MMK/JPY) it behaves byte-identically to the digits-only
/// formatter above (no regression for any existing shop); for exponent > 0
/// (THB/USD/…) it also allows a single '.' followed by up to [exponent]
/// fractional digits, grouping only the whole-unit part with thousands
/// separators.
class DecimalMoneyInputFormatter extends TextInputFormatter {
  const DecimalMoneyInputFormatter({required this.exponent});
  final int exponent;

  static const String _sep = ',';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (exponent <= 0) {
      return ThousandsSeparatorInputFormatter()
          .formatEditUpdate(oldValue, newValue);
    }
    final raw = _rawDecimalOf(newValue.text);
    final dotIndex = raw.indexOf('.');
    final whole = dotIndex < 0 ? raw : raw.substring(0, dotIndex);
    var frac = dotIndex < 0 ? '' : raw.substring(dotIndex + 1);
    if (frac.length > exponent) frac = frac.substring(0, exponent);
    final groupedWhole = ThousandsSeparatorInputFormatter.formatThousandsText(whole);
    final formatted = dotIndex < 0 ? groupedWhole : '$groupedWhole.$frac';
    if (formatted == newValue.text) return newValue;

    // Same caret-relative-to-digits approach as the whole-unit formatter,
    // also skipping over the decimal point when walking the output.
    final clamped = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    final digitsBeforeCaret =
        _rawDecimalOf(newValue.text.substring(0, clamped)).replaceAll('.', '').length;
    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCaret) {
      if (formatted[offset] != _sep && formatted[offset] != '.') seen++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// "1,234.56" → 123456 (minor units) for [exponent] 2; anything unparsable
/// or an absurd digit run clamps to [maxMoneyInputKyat] instead of
/// wrapping to null→0 (same audit QA-L3 guarantee as [parseThousands]).
/// For exponent 0 this is exactly [parseThousands].
int parseDecimalMinorUnits(String s, {required int exponent}) {
  if (exponent <= 0) return parseThousands(s);
  final raw = _rawDecimalOf(s);
  if (raw.isEmpty || raw == '.') return 0;
  final dotIndex = raw.indexOf('.');
  final wholeStr = dotIndex < 0 ? raw : raw.substring(0, dotIndex);
  var fracStr = dotIndex < 0 ? '' : raw.substring(dotIndex + 1);
  fracStr = fracStr.length >= exponent
      ? fracStr.substring(0, exponent)
      : fracStr.padRight(exponent, '0');
  final whole = int.tryParse(wholeStr.isEmpty ? '0' : wholeStr);
  // A too-long digit run either fails to parse outright, or parses into a
  // value so large that `whole * scale` below would overflow Dart's 64-bit
  // int and silently wrap to a large NEGATIVE number, defeating the clamp
  // entirely (a pasted 17-18 digit whole part used to produce exactly that).
  // Clamping here, before the multiply, means the overflow itself can never
  // happen — any whole part already at or past the cap makes the final
  // minor-units value at least as large, for any non-negative exponent.
  if (whole == null || whole > maxMoneyInputKyat) return maxMoneyInputKyat;
  final frac = int.tryParse(fracStr.isEmpty ? '0' : fracStr) ?? 0;
  final minor = whole * _decimalPow10(exponent) + frac;
  return minor > maxMoneyInputKyat ? maxMoneyInputKyat : minor;
}

/// 123456 (minor units) → "1,234.56" for [exponent] 2 — for writing a
/// programmatic amount into a formatted field so it displays exactly like
/// user-typed text. For exponent 0 this is exactly [formatThousands].
String formatDecimalMinorUnits(int minor, {required int exponent}) {
  if (exponent <= 0) return formatThousands(minor);
  if (minor <= 0) return '';
  final scale = _decimalPow10(exponent);
  final whole = minor ~/ scale;
  final frac = minor % scale;
  final fracStr = frac.toString().padLeft(exponent, '0');
  final groupedWhole = ThousandsSeparatorInputFormatter.formatThousandsText('$whole');
  return '$groupedWhole.$fracStr';
}
