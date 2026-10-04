// International payment gateway (Lemon Squeezy) configuration, decided by the
// server. A customer's request never says which mode to charge in, and the
// duration they receive is never taken from the plan they asked for.

/// The production project. Test charges there must never grant real time.
const PRODUCTION_HOST = "gnikispsurwrmkspuisj.supabase.co";

/// True only on a non-production project that explicitly opted into the
/// processor's test mode. Throws `test_mode_not_allowed` if production (or an
/// unidentifiable project) has the flag set, so a stray secret fails loudly at
/// checkout time instead of quietly accepting test money as real.
export function gatewayTestMode(): boolean {
  const test = Deno.env.get("LEMONSQUEEZY_TEST_MODE") === "true";
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

export type GatewayPlan = "monthly" | "yearly";

/// What a verified variant turned out to be worth, in months of Premium.
export interface VerifiedVariant {
  variantId: string;
  months: number;
}

const PLAN_INTERVAL: Record<GatewayPlan, string> = {
  monthly: "month",
  yearly: "year",
};
const INTERVAL_MONTHS: Record<string, number> = { month: 1, year: 12 };

/// Confirms with the processor that `variantId` is a published, recurring
/// subscription whose interval matches `plan`, inside the configured store and
/// in the expected mode — then reports the months that interval is worth.
///
/// This is the only thing standing between a mistyped
/// `pay.lemonsqueezy.variant_*` config row and a customer paying one month's
/// price for a year of Premium: the duration comes from the variant the
/// processor will actually charge, not from the plan the client asked for. A
/// wrong mapping makes checkout unavailable instead of mispricing a term.
export async function verifyVariantForPlan(
  apiKey: string,
  storeId: string,
  variantId: string,
  plan: GatewayPlan,
  testMode: boolean,
): Promise<VerifiedVariant | { error: string }> {
  if (!/^\d+$/.test(variantId)) return { error: "variant_not_numeric" };
  const variant = await gatewayGet(apiKey, `variants/${variantId}`);
  if ("error" in variant) return variant;
  const attrs = variant.attributes ?? {};
  if (attrs.status !== "published") return { error: "variant_not_published" };
  if (attrs.is_subscription !== true) return { error: "variant_not_recurring" };
  if (attrs.interval !== PLAN_INTERVAL[plan]) {
    return { error: "variant_interval_mismatch" };
  }
  // A 3-month or 2-year variant would silently mis-term the renewal: the RPC
  // only renews in 1 or 12 month steps.
  if (Number(attrs.interval_count ?? 1) !== 1) {
    return { error: "variant_interval_count_unsupported" };
  }
  const productId = `${attrs.product_id ?? ""}`;
  if (!/^\d+$/.test(productId)) return { error: "variant_product_unknown" };
  // The variant itself does not carry a store, so the store (and therefore
  // whose money this is) is confirmed through its product.
  const product = await gatewayGet(apiKey, `products/${productId}`);
  if ("error" in product) return product;
  const productAttrs = product.attributes ?? {};
  if (`${productAttrs.store_id ?? ""}` !== storeId) {
    return { error: "variant_wrong_store" };
  }
  if ((productAttrs.test_mode ?? false) !== testMode) {
    return { error: "variant_wrong_mode" };
  }
  return { variantId, months: INTERVAL_MONTHS[attrs.interval] };
}

async function gatewayGet(
  apiKey: string,
  path: string,
): Promise<{ attributes?: Record<string, unknown> } | { error: string }> {
  let response: Response;
  try {
    response = await fetch(`https://api.lemonsqueezy.com/v1/${path}`, {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        Accept: "application/vnd.api+json",
      },
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    return { error: "processor_unavailable" };
  }
  if (!response.ok) {
    // 401/403 here means the key is for the other mode, or revoked.
    return { error: response.status === 404 ? "not_found" : "processor_unavailable" };
  }
  let body: unknown;
  try {
    body = await response.json();
  } catch {
    return { error: "processor_unavailable" };
  }
  const data = (body as { data?: { attributes?: Record<string, unknown> } })?.data;
  if (!data) return { error: "processor_unavailable" };
  return { attributes: data.attributes ?? {} };
}
