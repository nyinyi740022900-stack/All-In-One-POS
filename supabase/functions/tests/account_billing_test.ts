import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

// Exercise the real HTTP handlers. Only Auth/PostgREST are substituted; no
// production branch or renewal logic is replaced.
const handlers: Array<(r: Request) => Promise<Response>> = [];
const originalServe = Deno.serve;
Deno.serve = ((handler: (r: Request) => Promise<Response>) => {
  handlers.push(handler);
  return {};
}) as typeof Deno.serve;
Deno.env.set("SUPABASE_URL", "https://billing.test");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service");
Deno.env.set("SUPABASE_ANON_KEY", "test-anon");
await import("../storefront/index.ts");
await import("../admin/index.ts");
Deno.serve = originalServe;
const [storefront, admin] = handlers;

function request(body: unknown) {
  return new Request("https://billing.test/functions/v1/storefront", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "authorization": "Bearer test",
      "x-forwarded-for": "8.8.8.8",
    },
    body: JSON.stringify(body),
  });
}

Deno.test("anonymous device reference cannot purchase Premium", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (() =>
    Promise.resolve(
      Response.json({ message: "unauthorized" }, { status: 401 }),
    )) as typeof fetch;
  try {
    const response = await storefront(
      request({
        action: "submit_license_request",
        device_id: "public-id",
        shop_name: "Shop",
        plan: "monthly",
        months: 1,
        amount: 20000,
        ref_no: "123456",
      }),
    );
    assertEquals(response.status, 401);
    assertEquals((await response.json()).error, "not_authenticated");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("lapsed subscription rejects new storefront orders before writing an order", async () => {
  const originalFetch = globalThis.fetch;
  const writes: string[] = [];
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = `${input}`;
    if (init?.method === "POST") writes.push(url);
    if (url.includes("/storefronts?")) {
      return Promise.resolve(
        Response.json({
          shop_id: "shop-a",
          enabled: true,
          hours_enabled: false,
        }),
      );
    }
    if (url.includes("/shop_subscriptions?")) {
      return Promise.resolve(
        Response.json({
          shop_id: "shop-a",
          plan: "monthly",
          expires_at: "2020-01-01T00:00:00Z",
          is_archived: false,
        }),
      );
    }
    return Promise.resolve(Response.json([]));
  }) as typeof fetch;
  try {
    const response = await storefront(
      request({ action: "submit_order", slug: "shop-a", items: [] }),
    );
    assertEquals(response.status, 403);
    assertEquals((await response.json()).error, "subscription_lapsed");
    assertEquals(writes, []);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("fulfilled payment retry returns stored expiry without issuing another key or term", async () => {
  const originalFetch = globalThis.fetch;
  const calls: string[] = [];
  globalThis.fetch = ((input: RequestInfo | URL) => {
    const url = `${input}`;
    calls.push(url);
    if (url.includes("/auth/v1/user")) {
      return Promise.resolve(
        Response.json({ id: "admin", app_metadata: { role: "admin" } }),
      );
    }
    if (url.includes("/rpc/fulfill_account_payment")) {
      return Promise.resolve(
        Response.json({
          ok: true,
          duplicate: true,
          expires_at: "2027-01-01T00:00:00Z",
        }),
      );
    }
    if (url.includes("/license_requests?")) {
      return Promise.resolve(
        Response.json({
          id: "request-a",
          shop_id: "shop-a",
          status: "fulfilled",
          fulfilled_expires_at: "2027-01-01T00:00:00Z",
          months: 1,
        }),
      );
    }
    return Promise.resolve(Response.json([]));
  }) as typeof fetch;
  try {
    const response = await admin(
      request({ action: "fulfill_request", request_id: "request-a" }),
    );
    assertEquals(response.status, 200);
    const data = await response.json();
    assertEquals(data.expires_at, "2027-01-01T00:00:00Z");
    assertEquals(data.duplicate, true);
    assertEquals(
      calls.some((c) =>
        c.includes("/rpc/create_license") || c.includes("/rpc/renew_license")
      ),
      false,
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("owner cannot buy for another shop or choose their own amount", async () => {
  const originalFetch = globalThis.fetch;
  let submitted: Record<string, unknown> | null = null;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = `${input}`;
    if (url.includes("/auth/v1/user")) {
      return Promise.resolve(
        Response.json({
          id: "owner-a",
          app_metadata: { role: "owner", shop_id: "shop-a" },
        }),
      );
    }
    if (url.includes("/org_branches?")) {
      return Promise.resolve(Response.json([]));
    }
    if (url.includes("/shop_subscriptions?")) {
      return Promise.resolve(
        Response.json([{ shop_id: "shop-a", plan: "free" }]),
      );
    }
    if (url.includes("/license_requests?")) {
      return Promise.resolve(Response.json(null));
    }
    if (url.endsWith("/license_requests")) {
      submitted = JSON.parse(`${init?.body}`);
      return Promise.resolve(Response.json(null));
    }
    if (init?.method === "HEAD") {
      return Promise.resolve(
        new Response(null, { headers: { "content-range": "0-0/0" } }),
      );
    }
    return Promise.resolve(Response.json(null));
  }) as typeof fetch;
  const body = {
    action: "submit_license_request",
    shop_id: "shop-b",
    client_request_id: "ae362371-2408-43e8-8e5f-7343c5c85342",
    plan: "yearly",
    months: 60,
    amount: 1,
    method: "kbzpay",
    ref_no: "123456",
  };
  try {
    assertEquals((await storefront(request(body))).status, 403);
    const response = await storefront(request({ ...body, shop_id: "shop-a" }));
    assertEquals(response.status, 200);
    assertEquals(submitted?.["amount"], 200000);
    assertEquals(submitted?.["months"], 12);
    assertEquals(submitted?.["owner_user_id"], "owner-a");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("admin cannot unlink the subscription owner by changing Auth metadata", async () => {
  const originalFetch = globalThis.fetch;
  let changed = false;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = `${input}`;
    if (init?.method === "PUT") changed = true;
    if (url.endsWith("/auth/v1/user")) {
      return Promise.resolve(
        Response.json({ id: "admin", app_metadata: { role: "admin" } }),
      );
    }
    if (url.includes("/auth/v1/admin/users/")) {
      return Promise.resolve(
        Response.json({
          id: "00000000-0000-4000-8000-000000000001",
          app_metadata: { role: "owner", shop_id: "shop-a" },
        }),
      );
    }
    if (url.includes("/auth/v1/admin/users?")) {
      return Promise.resolve(
        Response.json({
          users: [{
            id: "someone-else",
            app_metadata: { role: "owner", shop_id: "shop-a" },
          }],
        }),
      );
    }
    if (url.includes("/shop_subscriptions?")) {
      return Promise.resolve(Response.json([{ shop_id: "shop-a" }]));
    }
    return Promise.resolve(Response.json({}));
  }) as typeof fetch;
  try {
    const response = await admin(
      request({
        action: "unlink_account",
        user_id: "00000000-0000-4000-8000-000000000001",
      }),
    );
    assertEquals(response.status, 400);
    assertEquals((await response.json()).error, "last_owner");
    assertEquals(changed, false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("admin config rejects nonnumeric gateway variants before any public write", async () => {
  const originalFetch = globalThis.fetch;
  let writes = 0;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    if (`${input}`.includes("/auth/v1/user")) {
      return Promise.resolve(
        Response.json({ id: "admin", app_metadata: { role: "admin" } }),
      );
    }
    if (init?.method === "POST") writes++;
    return Promise.resolve(Response.json([]));
  }) as typeof fetch;
  try {
    for (const variant of ["https://checkout.example", "0", "-2", "1.5"]) {
      const response = await admin(
        request({
          action: "set_config",
          config: { "pay.lemonsqueezy.variant_monthly": variant },
        }),
      );
      assertEquals(response.status, 400);
      assertEquals((await response.json()).error, "invalid_config_value");
    }
    assertEquals(writes, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
