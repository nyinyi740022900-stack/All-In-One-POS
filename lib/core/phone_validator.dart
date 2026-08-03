/// Loose check for whether [value] looks like a Myanmar phone number —
/// local (09XXXXXXXXX) or international (+959XXXXXXXXX/959XXXXXXXXX)
/// mobile format. Deliberately lenient (7-9 digits after the 9 covers both
/// older 7-digit and newer 9-digit MPT/Telenor/Ooredoo/Mytel numbers) and
/// non-blocking by design — this is meant to catch an obvious typo with a
/// hint, not reject a legitimate landline or foreign supplier number, so
/// callers should show it as a helper/warning text, never as a save-blocking
/// form validator. An empty value is always considered fine (phone is
/// optional everywhere it's collected).
bool looksLikeMyanmarPhone(String value) {
  final v = value.trim().replaceAll(RegExp(r'[\s-]'), '');
  if (v.isEmpty) return true;
  return RegExp(r'^09\d{7,9}$').hasMatch(v) ||
      RegExp(r'^\+?959\d{7,9}$').hasMatch(v);
}
