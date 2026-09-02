/// A POS currency a shop can sell in — code, decimal precision, and the
/// symbol shown on receipts/screens. One shop has exactly one [CurrencyDef]
/// (never attached per-`Money` instance, only looked up once from the
/// shop's `currency_code` via `shopCurrencyProvider`).
///
/// Deliberately a small curated list, not a full ISO 4217 table — the owner
/// asked to switch between Ks/THB/$/¥, not to support every world currency.
/// This is still one currency per shop, just a wider menu of ones (no FX,
/// no dual-currency cart/ledger — see the currency-foundation plan).
class CurrencyDef {
  /// ISO 4217 code — the value stored in `ShopProfiles.currencyCode` /
  /// Postgres `shop_profiles.currency_code`.
  final String code;

  /// Decimal places minor-unit arithmetic implies for this currency.
  /// MMK/JPY = 0 (no commonly-used minor unit); THB/USD = 2.
  final int exponent;

  /// Glyph shown on-screen and on thermal receipts.
  final String symbol;

  /// Myanmar-language variant of [symbol] — only meaningful for MMK
  /// (existing Ks/ကျပ် toggle). Null for every other currency: its [symbol]
  /// is shown regardless of UI language, since UI language must not pick
  /// MMK vs THB.
  final String? symbolMy;

  const CurrencyDef({
    required this.code,
    required this.exponent,
    required this.symbol,
    this.symbolMy,
  });

  /// The on-screen suffix for the given UI locale code ('en'/'my').
  String label(String localeCode) =>
      (localeCode == 'my' && symbolMy != null) ? symbolMy! : symbol;

  static const mmk =
      CurrencyDef(code: 'MMK', exponent: 0, symbol: 'Ks', symbolMy: 'ကျပ်');
  static const thb = CurrencyDef(code: 'THB', exponent: 2, symbol: '฿');
  static const usd = CurrencyDef(code: 'USD', exponent: 2, symbol: r'$');
  static const jpy = CurrencyDef(code: 'JPY', exponent: 0, symbol: '¥');

  /// The curated, pickable set — order matches the Shop Profile dropdown.
  static const all = [mmk, thb, usd, jpy];

  /// Fail-closed to MMK for an unknown/empty/legacy code — never blank,
  /// never throw in the sell path.
  static CurrencyDef byCode(String? code) =>
      all.firstWhere((c) => c.code == code, orElse: () => mmk);
}
