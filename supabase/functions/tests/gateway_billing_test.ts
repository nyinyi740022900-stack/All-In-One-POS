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
