/// The `app_config` keys the admin console may edit, with the label shown for
/// each.
///
/// `app_config` is **world-readable** — migration 0006 gives it
/// `for select to anon, authenticated using (true)` on purpose, so a shop that
/// has not signed in yet can still see where to send its renewal payment.
/// Every key here is therefore public information by design. Nothing secret
/// may be added to this map: an API key or webhook secret typed into the
/// config editor would be readable by anyone on the internet the moment it
/// saved.
///
/// The Edge Function keeps its own copy (`PUBLIC_CONFIG_KEYS` in
/// `supabase/functions/admin/index.ts`) and rejects anything outside it, so
/// the browser is not the only thing enforcing this.
/// `admin_config_keys_test.dart` fails if the two lists drift apart, or if the
/// app reads a config key the console has no way to set — which is how the
/// four Lemon Squeezy keys and the two device-allowance keys below sat
/// unreachable behind the Supabase SQL editor, the console offering only
/// seven of the thirteen keys the product actually runs on.
library;

const Map<String, String> kAdminConfigKeys = {
  // --- Myanmar manual payment (shown on /renew and in-app) -----------------
  'pay.kbzpay.name': 'KBZPay account name',
  'pay.kbzpay.number': 'KBZPay number',
  'pay.wavepay.name': 'WavePay account name',
  'pay.wavepay.number': 'WavePay number',
  'support.viber': 'Support Viber number',

  // Myanmar prices and the included three devices are product constants.

  // --- International Premium via Lemon Squeezy ----------------------------
  // Store slug and variant ids are public checkout identifiers, not secrets —
  // they appear in the checkout URL the customer's own browser opens. The
  // signing secret that verifies the webhook is a Supabase secret and is NOT
  // here, and must never be.
  'pay.lemonsqueezy.variant_monthly': 'Lemon Squeezy monthly variant id',
  'pay.lemonsqueezy.variant_yearly': 'Lemon Squeezy yearly variant id',
};

/// Longest licence term the admin console will submit, in months — the mirror
/// of `MAX_LICENCE_MONTHS` in `supabase/functions/admin/index.ts`.
///
/// The server is the real guard; this exists so a typo is caught in the form,
/// beside the field, instead of coming back as an opaque `months_too_large`
/// after the dialog has closed.
const int kMaxLicenceMonths = 12;
