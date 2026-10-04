import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
let handler: (r: Request) => Promise<Response>;
const serve = Deno.serve;
Deno.serve = ((h: typeof handler) => {
  handler = h;
  return {};
}) as typeof Deno.serve;
Deno.env.set("SUPABASE_URL", "https://billing.test");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service");
Deno.env.set("LEMONSQUEEZY_WEBHOOK_SECRET", "test-secret");
Deno.env.set("LEMONSQUEEZY_API_KEY", "test-api");
Deno.env.set("LEMONSQUEEZY_STORE_ID", "1");
await import("../lemonsqueezy-webhook/index.ts");
Deno.serve = serve;
async function deliver(
  event: string,
  attrs: Record<string, unknown> = {},
  custom: Record<string, unknown> = {},
) {
  const body = JSON.stringify({
    meta: { event_name: event, custom_data: custom },
    data: { id: "invoice1", attributes: attrs },
  });
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode("test-secret"),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)),
  );
  const sig = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  return handler(
    new Request("https://billing.test", {
      method: "POST",
      headers: { "x-signature": sig },
      body,
    }),
  );
}
Deno.test("order-created event never grants time alongside initial subscription invoice", async () => {
  const response = await deliver("order_created", { status: "paid" }, {
    shop_id: "public-shop",
  });
  assertEquals(response.status, 200);
  assertEquals((await response.json()).ignored, "order_created");
});
Deno.test("paid subscription invoice uses verified checkout and atomic invoice identity", async () => {
  const original = globalThis.fetch;
  let rpc: Record<string, unknown> | null = null;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = `${input}`;
    if (url.includes("api.lemonsqueezy.com")) {
      return Promise.resolve(
        Response.json({
          data: {
            attributes: { store_id: 1, variant_id: 10, test_mode: false },
          },
        }),
      );
    }
    if (url.includes("/billing_checkouts?")) {
      return Promise.resolve(
        Response.json({
          id: "checkout1",
          shop_id: "shop-a",
          variant_id: "10",
          months: 1,
        }),
      );
    }
    if (url.includes("/rpc/fulfill_gateway_payment")) {
      rpc = JSON.parse(`${init?.body}`);
      return Promise.resolve(
        Response.json({ ok: true, duplicate: true, expires_at: "2027-01-01" }),
      );
    }
    return Promise.resolve(Response.json(null));
  }) as typeof fetch;
  try {
    const response = await deliver("subscription_payment_success", {
      store_id: 1,
      subscription_id: 99,
      status: "paid",
      billing_reason: "initial",
      test_mode: false,
    }, { billing_id: "checkout1", shop_id: "attacker-shop" });
    assertEquals(response.status, 200);
    assertEquals(rpc?.["p_invoice_id"], "invoice1");
    assertEquals(rpc?.["p_checkout_id"], "checkout1");
    assertEquals((await response.json()).duplicate, true);
  } finally {
    globalThis.fetch = original;
  }
});

/// A processor whose subscription lookup answers with `subscription`, plus a
/// verified checkout binding. Records whether fulfilment was reached.
function stubPaidSubscription(subscription: Record<string, unknown>) {
  const original = globalThis.fetch;
  const fulfilled: string[] = [];
  globalThis.fetch = ((input: RequestInfo | URL) => {
    const url = `${input}`;
    if (url.includes("api.lemonsqueezy.com")) {
      return Promise.resolve(Response.json({ data: { attributes: subscription } }));
    }
    if (url.includes("/billing_checkouts?")) {
      return Promise.resolve(
        Response.json({
          id: "checkout1",
          shop_id: "shop-a",
          variant_id: "10",
          months: 1,
        }),
      );
    }
    if (url.includes("/rpc/fulfill_gateway_payment")) {
      fulfilled.push(url);
      return Promise.resolve(Response.json({ ok: true, expires_at: "2027-01-01" }));
    }
    return Promise.resolve(Response.json(null));
  }) as typeof fetch;
  return {
    fulfilled,
    restore: () => {
      globalThis.fetch = original;
    },
  };
}

const LIVE_SUBSCRIPTION = { store_id: 1, variant_id: 10, test_mode: false };
const PAID_INVOICE = {
  store_id: 1,
  subscription_id: 99,
  status: "paid",
  billing_reason: "renewal",
};

Deno.test("a live service refuses a processor test charge and grants nothing", async () => {
  const stub = stubPaidSubscription(LIVE_SUBSCRIPTION);
  try {
    const response = await deliver("subscription_payment_success", {
      ...PAID_INVOICE,
      test_mode: true,
    }, { billing_id: "checkout1" });
    assertEquals(response.status, 400);
    assertEquals((await response.json()).error, "test_payment_not_live");
    assertEquals(stub.fulfilled, []);
  } finally {
    stub.restore();
  }
});

Deno.test("a live invoice on a test-mode subscription is refused too", async () => {
  // The invoice can claim live while the subscription behind it is test money.
  const stub = stubPaidSubscription({ ...LIVE_SUBSCRIPTION, test_mode: true });
  try {
    const response = await deliver("subscription_payment_success", {
      ...PAID_INVOICE,
      test_mode: false,
    }, { billing_id: "checkout1" });
    assertEquals(response.status, 409);
    assertEquals((await response.json()).error, "checkout_variant_mismatch");
    assertEquals(stub.fulfilled, []);
  } finally {
    stub.restore();
  }
});

Deno.test("a staging project accepts the test charge it opted into", async () => {
  Deno.env.set("LEMONSQUEEZY_TEST_MODE", "true"); // SUPABASE_URL here is not production
  const stub = stubPaidSubscription({ ...LIVE_SUBSCRIPTION, test_mode: true });
  try {
    const response = await deliver("subscription_payment_success", {
      ...PAID_INVOICE,
      test_mode: true,
    }, { billing_id: "checkout1" });
    assertEquals(response.status, 200);
    assertEquals(stub.fulfilled.length, 1);
    // ...and the live charge it is no longer expecting is refused.
    const live = await deliver("subscription_payment_success", {
      ...PAID_INVOICE,
      test_mode: false,
    }, { billing_id: "checkout1" });
    assertEquals(live.status, 400);
    assertEquals(stub.fulfilled.length, 1);
  } finally {
    stub.restore();
    Deno.env.delete("LEMONSQUEEZY_TEST_MODE");
  }
});

Deno.test("production with a stray test-mode secret fulfils nothing at all", async () => {
  const previousUrl = Deno.env.get("SUPABASE_URL") ?? "";
  Deno.env.set("SUPABASE_URL", "https://gnikispsurwrmkspuisj.supabase.co");
  Deno.env.set("LEMONSQUEEZY_TEST_MODE", "true");
  const stub = stubPaidSubscription(LIVE_SUBSCRIPTION);
  try {
    for (const testMode of [true, false]) {
      const response = await deliver("subscription_payment_success", {
        ...PAID_INVOICE,
        test_mode: testMode,
      }, { billing_id: "checkout1" });
      assertEquals(response.status, 503);
      assertEquals((await response.json()).error, "gateway_not_configured");
    }
    assertEquals(stub.fulfilled, []);
  } finally {
    stub.restore();
    Deno.env.delete("LEMONSQUEEZY_TEST_MODE");
    Deno.env.set("SUPABASE_URL", previousUrl);
  }
});
