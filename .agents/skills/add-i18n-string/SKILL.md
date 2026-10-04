---
name: add-i18n-string
description: Add (or change) a localized UI string in All In One POS — English + Myanmar together. Use when adding ANY user-facing text. Parity between the two ARB files is enforced by a test, so never add to just one.
---

# Add a localized string

Every string exists in BOTH ARB files. `i18n_parity_test.dart` fails on a
missing key, an empty value, or mismatched placeholders.

## Steps
1. Add the key to `lib/l10n/app_en.arb` (English).
2. Add the SAME key to `lib/l10n/app_my.arb` (Myanmar) — real translation, not
   a copy of the English.
3. For a placeholder string, add the `@key` metadata in BOTH files:
   ```json
   "creditOwed": "Owed {amount}",
   "@creditOwed": { "placeholders": { "amount": { "type": "String" } } },
   ```
   (`type: "int"` for counts, `"String"` for pre-formatted values.)
4. Regenerate: `flutter gen-l10n`
5. Use it: `AppLocalizations.of(context).creditOwed(x)`.
6. Verify: `flutter test test/i18n_parity_test.dart`.

## Conventions
- Keys are camelCase, prefixed by feature (`sell…`, `license…`, `credit…`,
  `analytics…`).
- Money/counts: pass the value; format with `Money(...).withSymbol(l.currencySymbol)`
  at the call site, not inside the ARB.
- Myanmar text: keep it natural/short for small buttons; the TextField helper in
  forms already adds vertical padding for tall stacked glyphs.
