import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

// The storefront handler is exercised for real; only Auth/PostgREST and the
// processor API are substituted.
const handlers: Array<(r: Request) => Promise<Response>> = [];
const originalServe = Deno.serve;
Deno.serve = ((handler: (r: Request) => Promise<Response>) => {
  handlers.push(handler);
  return {};
}) as typeof Deno.serve;
Deno.env.set("SUPABASE_URL", "https://staging.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service");
Deno.env.set("SUPABASE_ANON_KEY", "test-anon");
Deno.env.set("LEMONSQUEEZY_API_KEY", "test-api");
Deno.env.set("LEMONSQUEEZY_STORE_ID", "461190");
await import("../storefront/index.ts");
Deno.serve = originalServe;
const [storefront] = handlers;

const { gatewayTestMode, verifyVariantForPlan } = await import(
  "../_shared/gateway_mode.ts"
);

const PRODUCTION_URL = "https://gnikispsurwrmkspuisj.supabase.co";
const MONTHLY = "100", YEARLY = "200";

function withEnv(url: string, testMode: string | null, body: () => void) {
  const previousUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const previousMode = Deno.env.get("LEMONSQUEEZY_TEST_MODE");
  Deno.env.set("SUPABASE_URL", url);
  if (testMode === null) Deno.env.delete("LEMONSQUEEZY_TEST_MODE");
  else Deno.env.set("LEMONSQUEEZY_TEST_MODE", testMode);
  try {
    body();
  } finally {
    Deno.env.set("SUPABASE_URL", previousUrl);
    if (previousMode === undefined) Deno.env.delete("LEMONSQUEEZY_TEST_MODE");
    else Deno.env.set("LEMONSQUEEZY_TEST_MODE", previousMode);
  }
}

Deno.test("gateway mode defaults to live when nothing opts in", () => {
  withEnv(PRODUCTION_URL, null, () => assertEquals(gatewayTestMode(), false));
  withEnv("https://staging.supabase.co", null, () => assertEquals(gatewayTestMode(), false));
  // Anything other than the exact string stays live.
  withEnv("https://staging.supabase.co", "TRUE", () => assertEquals(gatewayTestMode(), false));
  withEnv("https://staging.supabase.co", "1", () => assertEquals(gatewayTestMode(), false));
});

Deno.test("only a non-production project may opt into test charges", () => {
  withEnv("https://staging.supabase.co", "true", () => assertEquals(gatewayTestMode(), true));
  // Production with the flag set is a configuration error, never test mode.
  withEnv(PRODUCTION_URL, "true", () =>
    assertThrows(() => gatewayTestMode(), Error, "test_mode_not_allowed"));
  // An unidentifiable project is treated as production.
  withEnv("", "true", () =>
    assertThrows(() => gatewayTestMode(), Error, "test_mode_not_allowed"));
  withEnv("not-a-url", "true", () =>
    assertThrows(() => gatewayTestMode(), Error, "test_mode_not_allowed"));
});

/// A processor whose variants/products answer as configured.
function stubProcessor(
  variants: Record<string, Record<string, unknown>>,
  products: Record<string, Record<string, unknown>> = {
    "9": { store_id: 461190, test_mode: false },
  },
) {
  const original = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL) => {
    const url = `${input}`;
    const variant = url.match(/\/v1\/variants\/(\d+)/)?.[1];
    if (variant) {
      const attrs = variants[variant];
      if (!attrs) return Promise.resolve(Response.json({}, { status: 404 }));
      return Promise.resolve(Response.json({ data: { attributes: attrs } }));
    }
    const product = url.match(/\/v1\/products\/(\d+)/)?.[1];
    if (product) {
      const attrs = products[product];
      if (!attrs) return Promise.resolve(Response.json({}, { status: 404 }));
      return Promise.resolve(Response.json({ data: { attributes: attrs } }));
    }
    return Promise.resolve(Response.json(null));
  }) as typeof fetch;
  return () => {
    globalThis.fetch = original;
  };
}

const PUBLISHED_MONTHLY = {
  status: "published",
  is_subscription: true,
  interval: "month",
  interval_count: 1,
  product_id: 9,
};
const PUBLISHED_YEARLY = { ...PUBLISHED_MONTHLY, interval: "year" };

Deno.test("a verified variant reports the months its own interval is worth", async () => {
  const restore = stubProcessor({
    [MONTHLY]: PUBLISHED_MONTHLY,
    [YEARLY]: PUBLISHED_YEARLY,
  });
  try {
    assertEquals(
      await verifyVariantForPlan("k", "461190", MONTHLY, "monthly", false),
      { variantId: MONTHLY, months: 1 },
    );
    assertEquals(
      await verifyVariantForPlan("k", "461190", YEARLY, "yearly", false),
      { variantId: YEARLY, months: 12 },
    );
  } finally {
    restore();
  }
});

Deno.test("a misconfigured variant is refused rather than mis-termed", async () => {
  const cases: Array<[string, Record<string, unknown>, string, string]> = [
    // The config row that would sell a year for one month's price.
    ["yearly plan pointing at the monthly variant", PUBLISHED_MONTHLY, "yearly", "variant_interval_mismatch"],
    ["monthly plan pointing at the yearly variant", PUBLISHED_YEARLY, "monthly", "variant_interval_mismatch"],
    ["a one-off product, not a subscription", { ...PUBLISHED_MONTHLY, is_subscription: false }, "monthly", "variant_not_recurring"],
    ["a draft variant", { ...PUBLISHED_MONTHLY, status: "draft" }, "monthly", "variant_not_published"],
    ["a three-month interval the renewal cannot express", { ...PUBLISHED_MONTHLY, interval_count: 3 }, "monthly", "variant_interval_count_unsupported"],
    ["a variant with no product", { ...PUBLISHED_MONTHLY, product_id: null }, "monthly", "variant_product_unknown"],
  ];
  for (const [name, attrs, plan, expected] of cases) {
    const restore = stubProcessor({ [MONTHLY]: attrs });
    try {
      const result = await verifyVariantForPlan(
        "k",
        "461190",
        MONTHLY,
        plan as "monthly" | "yearly",
        false,
      );
      assertEquals(result, { error: expected }, name);
    } finally {
      restore();
    }
  }
});

Deno.test("a variant from another store or the other mode is refused", async () => {
  let restore = stubProcessor({ [MONTHLY]: PUBLISHED_MONTHLY }, {
    "9": { store_id: 999999, test_mode: false },
  });
  try {
    assertEquals(
      await verifyVariantForPlan("k", "461190", MONTHLY, "monthly", false),
      { error: "variant_wrong_store" },
    );
  } finally {
    restore();
  }
  restore = stubProcessor({ [MONTHLY]: PUBLISHED_MONTHLY }, {
    "9": { store_id: 461190, test_mode: true },
  });
  try {
    assertEquals(
      await verifyVariantForPlan("k", "461190", MONTHLY, "monthly", false),
      { error: "variant_wrong_mode" },
    );
  } finally {
    restore();
  }
});

Deno.test("an unknown variant or an unreachable processor never verifies", async () => {
  const restore = stubProcessor({});
  try {
    assertEquals(
      await verifyVariantForPlan("k", "461190", "404404", "monthly", false),
      { error: "not_found" },
    );
    assertEquals(
      await verifyVariantForPlan("k", "461190", "abc", "monthly", false),
      { error: "variant_not_numeric" },
    );
  } finally {
    restore();
  }
  const original = globalThis.fetch;
  globalThis.fetch = (() => Promise.reject(new Error("offline"))) as typeof fetch;
  try {
    assertEquals(
      await verifyVariantForPlan("k", "461190", MONTHLY, "monthly", false),
      { error: "processor_unavailable" },
    );
  } finally {
    globalThis.fetch = original;
  }
});

/// A signed-in owner of shop-a asking to buy `plan`, with the processor and
/// PostgREST stubbed. Returns the response plus the binding row that was
/// written, if any.
async function checkout(
  plan: string,
  variantConfig: Record<string, string>,
  variants: Record<string, Record<string, unknown>>,
) {
  const original = globalThis.fetch;
  let binding: Record<string, unknown> | null = null;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = `${input}`;
    if (url.includes("/auth/v1/user")) {
      return Promise.resolve(
        Response.json({ id: "owner-1", email: "o@example.com", app_metadata: { role: "owner" } }),
      );
    }
    if (url.includes("/shop_subscriptions?")) {
      return Promise.resolve(Response.json([
        { shop_id: "shop-a", shop_name: "Shop A", plan: "free", expires_at: "1970-01-01T00:00:00Z" },
      ]));
    }
    if (url.includes("/app_config?")) {
      const key = decodeURIComponent(url).match(/key=eq\.([^&]+)/)?.[1] ?? "";
      const value = variantConfig[key];
      return Promise.resolve(Response.json(value ? { value } : null));
    }
    if (url.includes("/billing_checkouts")) {
      binding = JSON.parse(`${init?.body}`);
      return Promise.resolve(Response.json({}, { status: 201 }));
    }
    const variant = url.match(/\/v1\/variants\/(\d+)/)?.[1];
    if (variant) {
      const attrs = variants[variant];
      if (!attrs) return Promise.resolve(Response.json({}, { status: 404 }));
      return Promise.resolve(Response.json({ data: { attributes: attrs } }));
    }
    if (url.match(/\/v1\/products\/(\d+)/)) {
      return Promise.resolve(
        Response.json({ data: { attributes: { store_id: 461190, test_mode: false } } }),
      );
    }
    if (url.includes("/v1/checkouts")) {
      return Promise.resolve(
        Response.json({ data: { attributes: { url: "https://pay.example.com/c/1" } } }),
      );
    }
    return Promise.resolve(Response.json(null));
  }) as typeof fetch;
  try {
    const response = await storefront(
      new Request("https://staging.supabase.co/functions/v1/storefront", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: "Bearer owner-token",
          "x-forwarded-for": "8.8.8.8",
        },
        body: JSON.stringify({ action: "create_checkout", shop_id: "shop-a", plan }),
      }),
    );
    return { response, binding: binding as Record<string, unknown> | null };
  } finally {
    globalThis.fetch = original;
  }
}

Deno.test("checkout stores the term the processor will charge, not the one asked for", async () => {
  const variants = { [MONTHLY]: PUBLISHED_MONTHLY, [YEARLY]: PUBLISHED_YEARLY };
  const config = {
    "pay.lemonsqueezy.variant_monthly": MONTHLY,
    "pay.lemonsqueezy.variant_yearly": YEARLY,
  };
  const monthly = await checkout("monthly", config, variants);
  assertEquals(monthly.response.status, 200);
  assertEquals(monthly.binding?.months, 1);
  assertEquals(monthly.binding?.variant_id, MONTHLY);
  const yearly = await checkout("yearly", config, variants);
  assertEquals(yearly.response.status, 200);
  assertEquals(yearly.binding?.months, 12);
  assertEquals(yearly.binding?.variant_id, YEARLY);
});

Deno.test("a yearly config row pointing at the monthly variant sells nothing", async () => {
  const { response, binding } = await checkout(
    "yearly",
    { "pay.lemonsqueezy.variant_yearly": MONTHLY },
    { [MONTHLY]: PUBLISHED_MONTHLY },
  );
  assertEquals(response.status, 503);
  assertEquals((await response.json()).error, "checkout_unavailable");
  // Nothing was bound, so a later invoice has no checkout to fulfil.
  assertEquals(binding, null);
});

Deno.test("an unset or non-numeric variant config sells nothing", async () => {
  const configs: Record<string, string>[] = [
    {},
    { "pay.lemonsqueezy.variant_monthly": "not-a-number" },
  ];
  for (const config of configs) {
    const { response, binding } = await checkout("monthly", config, {
      [MONTHLY]: PUBLISHED_MONTHLY,
    });
    assertEquals(response.status, 503);
    assertEquals(binding, null);
  }
});

Deno.test("production with a stray test-mode secret refuses to sell", async () => {
  Deno.env.set("LEMONSQUEEZY_TEST_MODE", "true");
  const previousUrl = Deno.env.get("SUPABASE_URL") ?? "";
  Deno.env.set("SUPABASE_URL", PRODUCTION_URL);
  try {
    const { response, binding } = await checkout(
      "monthly",
      { "pay.lemonsqueezy.variant_monthly": MONTHLY },
      { [MONTHLY]: PUBLISHED_MONTHLY },
    );
    assertEquals(response.status, 503);
    assertEquals((await response.json()).error, "checkout_unavailable");
    assertEquals(binding, null);
  } finally {
    Deno.env.delete("LEMONSQUEEZY_TEST_MODE");
    Deno.env.set("SUPABASE_URL", previousUrl);
  }
});
