/// A custom-named way customers can pay a shop — e.g. "KBZPay", "PayPal",
/// "PromptPay", "Bank Transfer" — with an account name/number to show them.
/// Replaces the old fixed KBZPay/WavePay-only fields on `ShopProfile` and
/// `storefronts.pay_kpay*`/`pay_wave*`, which assumed every shop is in
/// Myanmar; a shop elsewhere names whatever it actually uses.
class PaymentMethod {
  final String label;
  final String accountName;
  final String accountNumber;

  const PaymentMethod({
    required this.label,
    this.accountName = '',
    required this.accountNumber,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> m) => PaymentMethod(
        label: (m['label'] as String?) ?? '',
        accountName: (m['account_name'] as String?) ?? '',
        accountNumber: (m['account_number'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'account_name': accountName,
        'account_number': accountNumber,
      };

  /// Parses a JSON-decoded list (from local KV storage or the `storefronts`
  /// `payment_methods` jsonb column), dropping any entry with neither a
  /// label nor an account number — nothing useful to show a customer.
  static List<PaymentMethod> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => PaymentMethod.fromJson(e.cast<String, dynamic>()))
        .where((m) => m.label.isNotEmpty || m.accountNumber.isNotEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> listToJson(List<PaymentMethod> list) =>
      list.map((m) => m.toJson()).toList();
}
