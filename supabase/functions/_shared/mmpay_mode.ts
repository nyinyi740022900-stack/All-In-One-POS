// Myan Myan Pay (MMQR) configuration, decided by the server. Mirrors
// gateway_mode.ts: a customer's request never says which mode to charge in,
// and sandbox money must never buy a real month.

/// The production project. Test charges there must never grant real time.
const PRODUCTION_HOST = "gnikispsurwrmkspuisj.supabase.co";

/// True only on a non-production project that explicitly opted into MMPay's
/// sandbox. Throws `test_mode_not_allowed` if production (or an unidentifiable
/// project) has the flag set, so a stray secret fails loudly at checkout time
/// instead of quietly accepting sandbox money as real.
export function mmpayTestMode(): boolean {
  const test = Deno.env.get("MMPAY_TEST_MODE") === "true";
  if (!test) return false;
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  let host = "";
  try {
    host = new URL(url).hostname;
  } catch {
    host = "";
  }
  if (!host || host === PRODUCTION_HOST) {
    throw new Error("test_mode_not_allowed");
  }
  return true;
}

/// Everything an outbound MMPay call needs, or an `error` naming what is wrong.
///
/// MMPay's keys carry their own environment in their value (`pk_test_` /
/// `sk_test_` versus `pk_live_` / `sk_live_`). We check that tag against the
/// mode the *server* decided rather than letting the key decide, which is how
/// the published SDK does it — there, pasting a live key into a staging
/// project silently starts taking real money.
export interface MmpayConfig {
  appId: string;
  publishableKey: string;
  secretKey: string;
  baseUrl: string;
  testMode: boolean;
}

const DEFAULT_BASE_URL = "https://ezapi.myanmyanpay.com";

export function mmpayConfig(): MmpayConfig | { error: string } {
  let testMode: boolean;
  try {
    testMode = mmpayTestMode();
  } catch {
    return { error: "test_mode_not_allowed" };
  }
  const appId = Deno.env.get("MMPAY_APP_ID") ?? "";
  const publishableKey = Deno.env.get("MMPAY_PUBLISHABLE_KEY") ?? "";
  const secretKey = Deno.env.get("MMPAY_SECRET_KEY") ?? "";
  if (!appId || !publishableKey || !secretKey) {
    return { error: "mmpay_not_configured" };
  }
  const want = testMode ? "_test_" : "_live_";
  if (!publishableKey.startsWith(`pk${want}`)) {
    return { error: "mmpay_key_wrong_mode" };
  }
  if (!secretKey.startsWith(`sk${want}`)) {
    return { error: "mmpay_key_wrong_mode" };
  }
  const baseUrl = (Deno.env.get("MMPAY_BASE_URL") ?? DEFAULT_BASE_URL).replace(
    /\/+$/,
    "",
  );
  if (!baseUrl.startsWith("https://")) return { error: "mmpay_not_configured" };
  return { appId, publishableKey, secretKey, baseUrl, testMode };
}

/// Whether this project can offer an MMQR at all. Deliberately does not call
/// MMPay — a page asking "can I show the QR option?" should not wait on an
/// external API, and the order itself is verified when the owner actually buys.
export function mmpayAvailable(): boolean {
  return !("error" in mmpayConfig());
}
