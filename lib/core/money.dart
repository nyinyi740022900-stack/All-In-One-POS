import 'package:intl/intl.dart';

import 'currency_def.dart';
import 'input/thousands_formatter.dart';

/// Money value object — an integer count of *minor units* of whichever
/// currency the shop it belongs to has chosen ([CurrencyDef]). All
/// arithmetic stays in integers to avoid floating-point drift on money.
///
/// Deliberately currency-agnostic on the instance itself (no `currency`
/// field here) — a shop has exactly one [CurrencyDef] at a time
/// (`shopCurrencyProvider`), so formatting methods take it as a parameter
/// at the point of display rather than threading it through every
/// construction/arithmetic call site. For MMK (exponent 0) minor units are
/// numerically identical to whole kyat, so every existing shop's on-disk
/// integers and math are unchanged by this.
class Money implements Comparable<Money> {
  final int minor;

  const Money(this.minor);

  static const Money zero = Money(0);

  factory Money.fromString(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9-]'), '');
    final value = int.tryParse(cleaned);
    if (value == null) {
      // Audit QA-L3: an overlong digit run must not collapse to 0 — clamp
      // its magnitude so a pasted giant reads as "very large", not "free".
      final negative = cleaned.startsWith('-');
      return Money(negative ? -maxMoneyInputKyat : maxMoneyInputKyat);
    }
    return Money(value);
  }

  Money operator +(Money other) => Money(minor + other.minor);
  Money operator -(Money other) => Money(minor - other.minor);
  Money operator *(int qty) => Money(minor * qty);

  bool get isNegative => minor < 0;
  bool get isZero => minor == 0;

  /// e.g. exponent 0: `1,250`; exponent 2: `12.50`. Whole/fraction split
  /// uses integer div/mod (never double), so there's no float drift on the
  /// fractional part — only the whole-unit part goes through `NumberFormat`
  /// for thousands grouping.
  String formatted({int exponent = 0}) => formatMinorUnits(minor, exponent: exponent);

  /// e.g. `1,250 Ks` / `12.50 ฿` — pass a currency's localized label
  /// ([CurrencyDef.label]) or [withCurrency] to supply both symbol and
  /// exponent together.
  String withSymbol(String symbol, {int exponent = 0}) =>
      '${formatted(exponent: exponent)} $symbol';

  /// `withSymbol` for a specific shop currency + UI locale — the call most
  /// display sites should use.
  String withCurrency(CurrencyDef currency, String localeCode) =>
      withSymbol(currency.label(localeCode), exponent: currency.exponent);

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;

  @override
  int get hashCode => minor.hashCode;

  @override
  String toString() => 'Money($minor)';
}

final NumberFormat _wholeUnitFmt = NumberFormat('#,##0', 'en_US');

/// Formats a raw minor-unit integer for [exponent] with thousands grouping
/// on the whole-unit part — the same logic [Money.formatted] uses, exposed
/// standalone for the report/PDF classes that format a raw int rather than
/// a [Money] instance.
String formatMinorUnits(int minor, {int exponent = 0}) {
  if (exponent <= 0) return _wholeUnitFmt.format(minor);
  final negative = minor < 0;
  final abs = minor.abs();
  final scale = _pow10(exponent);
  final whole = abs ~/ scale;
  final frac = abs % scale;
  final fracStr = frac.toString().padLeft(exponent, '0');
  return '${negative ? '-' : ''}${_wholeUnitFmt.format(whole)}.$fracStr';
}

/// Formats a raw minor-unit integer for [exponent] as a *plain* numeric
/// string — no thousands grouping. Used for CSV cells, where a grouped
/// string like `1,250` would get comma-quoted and stop being a number a
/// spreadsheet can sum. For exponent 0 this is byte-identical to
/// `minor.toString()` — unchanged output for every existing MMK export.
String formatMinorUnitsPlain(int minor, {int exponent = 0}) {
  if (exponent <= 0) return minor.toString();
  final negative = minor < 0;
  final abs = minor.abs();
  final scale = _pow10(exponent);
  final whole = abs ~/ scale;
  final frac = abs % scale;
  final fracStr = frac.toString().padLeft(exponent, '0');
  return '${negative ? '-' : ''}$whole.$fracStr';
}

int _pow10(int exponent) {
  var v = 1;
  for (var i = 0; i < exponent; i++) {
    v *= 10;
  }
  return v;
}
