// Edge Function: public B2B2C storefront.
//
// Anonymous customers browse a shop's published catalog and place guest orders.
// The client only ever has the anon key; this function uses the service role
// internally so it can read products / write orders across shop-isolation RLS,
// while exposing ONLY safe fields (never secrets, never other shops' data).
//
// Actions:
//   catalog       { slug }  -> { storefront, products }
//   submit_order  { slug, customer_name, phone, address, township, note,
//                    payment_method ('transfer'|'cod'), payment_proof_path,
//                    lines[], hp } -> { ok, order_no }
//   submit_license_request { shop_name, device_id, email?, phone?, plan,
//                    months, method?, amount, ref_no (6-digit transaction
//                    suffix), payment_proof_path?, hp } -> { ok } — the
//                    /renew page's subscription-renewal
//                    request form. No slug/shop lookup (the shop isn't
//                    resolved yet, just a device_id the owner typed in, or
//                    optionally an account email that resolves to shop_id
//                    for an online-tier shop); writes a pending row to
//                    license_requests for the admin dashboard's Requests
//                    tab to pick up.
//   GET ?action=og&slug=… -> HTML Open Graph card (Facebook/Viber crawlers)
//
// Anti-abuse on submit_order: a hidden honeypot field (`hp`) catches
// blind-filling bots; at most 5 attempts per (shop, IP) per 10 minutes
// (`storefront_order_attempts`); a phone on the owner's block-list
// (`storefront_blocklist`) is rejected outright (403 `blocked`). Two
// different stock checks: a line over the shop's real recorded stock is
// still accepted, just flagged on `order_items.low_stock_at_order` for the
// owner to notice before packing (real stock can lag synced reality); a line
// over a product's owner-set `online_stock_limit` (a deliberate cap,
// independent of real stock, e.g. reserving only some units for online) IS
// hard-rejected (409 `out_of_stock`) — see `sumOrderedByProduct`.
// Opening hours (Asia/Yangon) and require_transfer_proof: see migration 0053.
//
// Deploy: supabase functions deploy storefront

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

// deno-lint-ignore no-explicit-any
function json(body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...CORS },
  });
}

function html(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { "content-type": "text/html; charset=utf-8", ...CORS },
  });
}

/** Minutes from midnight in Asia/Yangon (UTC+6:30). */
function yangonMinuteNow(): number {
  const now = Date.now();
  const yangon = new Date(now + 6.5 * 60 * 60 * 1000);
  // Use UTC getters after offset so we don't depend on Deno host TZ.
  return yangon.getUTCHours() * 60 + yangon.getUTCMinutes();
}

function isWithinHours(
  hoursEnabled: boolean,
  openMinute: number | null,
  closeMinute: number | null,
): boolean {
  if (!hoursEnabled) return true;
  if (openMinute == null || closeMinute == null) return true;
  const now = yangonMinuteNow();
  if (openMinute === closeMinute) return true; // 24h
  if (openMinute < closeMinute) {
    return now >= openMinute && now < closeMinute;
  }
  // Spans midnight (e.g. 22:00–06:00).
  return now >= openMinute || now < closeMinute;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// deno-lint-ignore no-explicit-any
type Admin = any;

/// For products that have an `online_stock_limit` set, sums how many units
/// are already spoken for by this shop's existing, non-cancelled storefront
/// orders — so the caller can compute what's left of the owner-set cap.
/// order_items has no DB-level FK to orders (plain text columns, see 0015),
/// so this can't use a single embedded-join query; it's two queries instead.
async function sumOrderedByProduct(
  admin: Admin,
  shopId: string,
  productIds: string[],
): Promise<Map<string, number>> {
  const ordered = new Map<string, number>();
  if (productIds.length === 0) return ordered;
  const { data: activeOrders } = await admin
    .from("orders")
    .select("id")
    .eq("shop_id", shopId)
    .eq("channel", "storefront")
    .eq("is_deleted", false)
    .neq("status", "cancelled");
  const orderIds = (activeOrders ?? []).map((o: { id: string }) => o.id);
  if (orderIds.length === 0) return ordered;
  const { data: orderedRows } = await admin
    .from("order_items")
    .select("product_id, qty")
    .in("product_id", productIds)
    .in("order_id", orderIds)
    .eq("is_deleted", false);
  for (const row of orderedRows ?? []) {
    const pid = row.product_id as string;
    ordered.set(pid, (ordered.get(pid) ?? 0) + (row.qty as number));
  }
  return ordered;
}

/// The /renew page's submission handler — a shop's own owner requesting a
/// subscription renewal/extension, identified only by the device_id ("App
/// Reference ID") they type in, not a slug or session. Restores a live path
/// into license_requests now that the in-app payment UI is gone (removed for
/// App Store 5.1.1(v) compliance, see the file header) — a web page isn't
/// subject to that rule. Mirrors submit_order's honeypot + rate-limit shape.
async function handleSubmitLicenseRequest(
  admin: Admin,
  // deno-lint-ignore no-explicit-any
  body: any,
  req: Request,
): Promise<Response> {
  // Honeypot: pretend success, write nothing — same convention as
  // submit_order, so a bot gets no signal it was caught.
  if (`${body.hp ?? ""}`.trim().length > 0) {
    return json({ ok: true });
  }

  // Rate limit: 5 per IP per 10 minutes. No shop_id to key on here (the
  // whole point of this entry point is that the shop isn't resolved yet) —
  // mirrors activate_attempts' IP-only shape, not submit_order's (shop_id,
  // ip) shape.
  const ip = (req.headers.get("x-forwarded-for") ?? "unknown")
    .split(",")[0]
    .trim();
  const windowStart = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { count } = await admin
    .from("license_request_attempts")
    .select("id", { count: "exact", head: true })
    .eq("ip", ip)
    .gte("created_at", windowStart);
  if ((count ?? 0) >= 5) {
    return json({ error: "rate_limited" }, 429);
  }
  await admin.from("license_request_attempts").insert({ ip });

  const shopName = `${body.shop_name ?? ""}`.trim();
  const deviceId = `${body.device_id ?? ""}`.trim();
  const emailPresent = `${body.email ?? ""}`.trim().length > 0;
  const months = Number(body.months);
  const amount = Number(body.amount);
  // Last 6 digits of the transaction number — required (not just optional
  // reference text) so a submitted request can actually be matched against
  // the vendor's own KBZPay/WavePay transaction history.
  const refNo = `${body.ref_no ?? ""}`.trim();
  if (
    !shopName || (!deviceId && !emailPresent) ||
    !Number.isInteger(months) || months <= 0 ||
    !Number.isInteger(amount) || amount <= 0 ||
    !/^\d{6}$/.test(refNo)
  ) {
    return json({ error: "bad_request" }, 400);
  }

  const rawPlan = `${body.plan ?? ""}`.trim();
  const plan = rawPlan === "yearly" ? "yearly" : "monthly";
  const rawMethod = `${body.method ?? ""}`.trim();
  const method = rawMethod === "kbzpay" || rawMethod === "wavepay"
    ? rawMethod
    : null;
  const phone = `${body.phone ?? ""}`.trim() || null;
  const proofPath = `${body.payment_proof_path ?? ""}`.trim() || null;
  // Renew-page proofs always live under `_admin/` (0066's folder scoping —
  // only the platform admin reads these). Reject any other prefix.
  if (proofPath && !proofPath.startsWith("_admin/")) {
    return json({ error: "bad_proof_path" }, 400);
  }

  // Optional: an online-tier shop (has a Supabase Auth account) can give
  // its account email instead of hunting for its device_id — resolves to
  // the exact shop via app_metadata.shop_id, so fulfill_request's existing
  // shop_id-first lookup renews precisely that shop (an account can have
  // multiple devices, unlike a device_id match, which only ever matches
  // one). Same page-and-match approach as list_shops — the Admin Auth API
  // has no filter-by-email call — and a bad/unmatched email just leaves
  // shopId null, silently falling back to the device_id path below.
  const email = `${body.email ?? ""}`.trim().toLowerCase();
  let shopId: string | null = null;
  if (email) {
    const { data: userPage } = await admin.auth.admin.listUsers({
      page: 1,
      perPage: 2000,
    });
    // deno-lint-ignore no-explicit-any
    const match = ((userPage?.users ?? []) as any[]).find(
      (u) => `${u.email ?? ""}`.toLowerCase() === email,
    );
    const meta = match?.app_metadata as Record<string, unknown> | undefined;
    shopId = (meta?.shop_id as string | undefined) ?? null;
  }

  const now = new Date().toISOString();
  const requestId = crypto.randomUUID();
  const { error } = await admin.from("license_requests").insert({
    id: requestId,
    shop_name: shopName,
    shop_id: shopId,
    device_id: deviceId,
    phone,
    plan,
    months,
    method,
    amount,
    ref_no: refNo,
    payment_proof_path: proofPath,
    // This entry point never has a Supabase Auth session — the resulting
    // key is always a device-key (offline-tier) activation, same as the
    // admin's own "Generate license key" default.
    tier: "offline",
    status: "pending",
    created_at: now,
    updated_at: now,
  });
  if (error) {
    return json({ error: "server_error", detail: error.message }, 500);
  }
  // The id is already known (generated above, before insert) — return it so
  // the /renew page can show the owner a reference number for their
  // submission, same as submit_order's order_no.
  return json({ ok: true, request_id: requestId });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return json({});

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceKey);
  const shopWebBase = "https://allinonepos-shop.vercel.app";

  // Open Graph HTML for link previews (crawlers use GET).
  if (req.method === "GET") {
    const u = new URL(req.url);
    if (u.searchParams.get("action") !== "og") {
      return json({ error: "method_not_allowed" }, 405);
    }
    const slug = (u.searchParams.get("slug") ?? "").trim();
    if (!slug) return html("<h1>Missing slug</h1>", 400);
    const { data: sf } = await admin
      .from("storefronts")
      .select("display_name, phone, address, logo_url, enabled")
      .eq("slug", slug)
      .maybeSingle();
    if (!sf || sf.enabled === false) {
      return html("<h1>Shop not found</h1>", 404);
    }
    const title = escapeHtml(sf.display_name || slug);
    const descParts = [sf.phone, sf.address].filter(Boolean);
    const desc = escapeHtml(
      descParts.length > 0
        ? descParts.join(" · ")
        : "Order online from this shop",
    );
    const pageUrl = `${shopWebBase}/${encodeURIComponent(slug)}`;
    const image = sf.logo_url
      ? escapeHtml(sf.logo_url as string)
      : `${shopWebBase}/icons/Icon-512.png`;
    return html(`<!DOCTYPE html>
<html><head>
<meta charset="utf-8"/>
<title>${title}</title>
<meta name="description" content="${desc}"/>
<meta property="og:type" content="website"/>
<meta property="og:title" content="${title}"/>
<meta property="og:description" content="${desc}"/>
<meta property="og:url" content="${pageUrl}"/>
<meta property="og:image" content="${image}"/>
<meta name="twitter:card" content="summary_large_image"/>
<meta http-equiv="refresh" content="0;url=${pageUrl}"/>
</head><body><p><a href="${pageUrl}">${title}</a></p></body></html>`);
  }

  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const action = body.action as string;

  // Dispatched before the slug lookup below: a subscription-renewal request
  // has no shop slug at all (the shop identifies itself only by the
  // device_id it types in) — see handleSubmitLicenseRequest.
  if (action === "submit_license_request") {
    return handleSubmitLicenseRequest(admin, body, req);
  }

  const slug = (body.slug ?? "").trim();
  if (!slug) return json({ error: "bad_request" }, 400);

  const { data: sf } = await admin
    .from("storefronts")
    .select("*")
    .eq("slug", slug)
    .eq("enabled", true)
    .maybeSingle();
  if (!sf) return json({ error: "not_found" }, 404);

  const acceptingOrders = isWithinHours(
    sf.hours_enabled === true,
    sf.open_minute as number | null,
    sf.close_minute as number | null,
  );

  if (action === "catalog") {
    const { data: products, error } = await admin
      .from("products")
      .select("id, name, sale_price, unit, image_url, online_stock_limit")
      .eq("shop_id", sf.shop_id)
      .eq("is_active", true)
      .eq("is_deleted", false)
      .order("name");
    if (error) return json({ error: "server_error" }, 500);

    const cappedIds = (products ?? [])
      .filter((p) => p.online_stock_limit != null)
      .map((p) => p.id as string);
    const ordered = await sumOrderedByProduct(admin, sf.shop_id, cappedIds);
    const productsOut = (products ?? []).map((p) => {
      if (p.online_stock_limit == null) return p;
      const available = Math.max(
        0,
        (p.online_stock_limit as number) - (ordered.get(p.id) ?? 0),
      );
      return { ...p, online_available: available };
    });

    return json({
      storefront: {
        // Needed by the guest page to upload its proof into the shop's own
        // `{shop_id}/` folder — the bucket read policy (0066) scopes every
        // shop to its folder, so the path must carry the shop_id prefix.
        // A bare UUID tenant key, not a secret (RLS still gates all reads).
        shop_id: sf.shop_id,
        display_name: sf.display_name,
        phone: sf.phone,
        address: sf.address,
        pay_kpay: sf.pay_kpay,
        pay_kpay_name: sf.pay_kpay_name,
        pay_wave: sf.pay_wave,
        pay_wave_name: sf.pay_wave_name,
        logo_url: sf.logo_url,
        accepting_orders: acceptingOrders,
        hours_enabled: sf.hours_enabled === true,
        open_minute: sf.open_minute ?? null,
        close_minute: sf.close_minute ?? null,
        require_transfer_proof: sf.require_transfer_proof !== false,
      },
      products: productsOut,
    });
  }

  if (action === "submit_order") {
    if (!acceptingOrders) {
      return json({ error: "closed" }, 403);
    }
    // Honeypot: a hidden field real customers never see or fill; only a
    // scripted form-filler touches it. Pretend success without writing
    // anything, so the bot gets no signal it was caught.
    if (`${body.hp ?? ""}`.trim().length > 0) {
      return json({ ok: true, order_no: "WEB-00000000" });
    }

    // Rate limit: at most 5 submit_order calls per (shop, IP) per 10
    // minutes — counted before validation, so rapid junk requests can't
    // dodge the limit just by being individually invalid.
    const ip = (req.headers.get("x-forwarded-for") ?? "unknown")
      .split(",")[0]
      .trim();
    const windowStart = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    const { count } = await admin
      .from("storefront_order_attempts")
      .select("id", { count: "exact", head: true })
      .eq("shop_id", sf.shop_id)
      .eq("ip", ip)
      .gte("created_at", windowStart);
    if ((count ?? 0) >= 5) {
      return json({ error: "rate_limited" }, 429);
    }
    await admin
      .from("storefront_order_attempts")
      .insert({ shop_id: sf.shop_id, ip });

    const name = (body.customer_name ?? "").trim();
    const phone = (body.phone ?? "").trim();
    // deno-lint-ignore no-explicit-any
    const rawLines = (body.lines ?? []) as any[];
    if (!name || rawLines.length === 0) {
      return json({ error: "bad_request" }, 400);
    }

    // Block-list: a phone the owner has blocked (usually after a scam/spam
    // order) can't place a new one. No phone at all means nothing to check —
    // an unidentifiable order isn't blockable by this mechanism.
    if (phone) {
      const { data: blocked } = await admin
        .from("storefront_blocklist")
        .select("phone")
        .eq("shop_id", sf.shop_id)
        .eq("phone", phone)
        .maybeSingle();
      if (blocked) return json({ error: "blocked" }, 403);
    }

    // 'transfer' (KPay/Wave, usually with a screenshot) or 'cod' (cash on
    // delivery) — anything else collapses to null (unspecified).
    const rawMethod = `${body.payment_method ?? ""}`.trim();
    const paymentMethod =
      rawMethod === "transfer" || rawMethod === "cod" ? rawMethod : null;

    const proofPath = `${body.payment_proof_path ?? ""}`.trim() || null;
    const requireProof = sf.require_transfer_proof !== false;
    if (paymentMethod === "transfer" && requireProof && !proofPath) {
      return json({ error: "proof_required" }, 400);
    }
    // The guest uploads into THIS shop's own `{shop_id}/` folder (0066
    // scopes bucket reads by that first path segment). Reject any other
    // prefix — a crafted path must not point at another tenant's folder or
    // an unviewable location.
    if (proofPath && !proofPath.startsWith(`${sf.shop_id}/`)) {
      return json({ error: "bad_proof_path" }, 400);
    }

    // Security: every line must name a real, active product belonging to
    // THIS shop, with a sane positive quantity. Price/name are never taken
    // from the client — a browser console can send anything — they're always
    // re-read from the product row so a submitted order can't under-price or
    // free-ride an item. (There's no free-text/custom-item path on the
    // storefront cart — every OrderLine the app builds already carries a
    // real catalog product_id.)
    const MAX_QTY = 999;
    const productIds = [
      ...new Set(
        rawLines
          .map((l) => `${l.product_id ?? ""}`.trim())
          .filter((id) => id.length > 0),
      ),
    ];
    if (productIds.length === 0) {
      return json({ error: "bad_request" }, 400);
    }
    for (const l of rawLines) {
      const qty = Number(l.qty);
      if (!Number.isInteger(qty) || qty <= 0 || qty > MAX_QTY) {
        return json({ error: "invalid_quantity" }, 400);
      }
    }

    const { data: products, error: pErr } = await admin
      .from("products")
      .select("id, name, sale_price, online_stock_limit")
      .eq("shop_id", sf.shop_id)
      .eq("is_active", true)
      .eq("is_deleted", false)
      .in("id", productIds);
    if (pErr) return json({ error: "server_error" }, 500);
    const byId = new Map((products ?? []).map((p) => [p.id, p]));

    // Stock check: never blocks the order (the storefront's cached stock can
    // lag the device's synced reality) — just flags a line for the owner to
    // notice before packing it, on `order_items.low_stock_at_order`.
    const { data: stockRows } = await admin
      .from("stock_levels")
      .select("product_id, quantity")
      .eq("shop_id", sf.shop_id)
      .eq("is_deleted", false)
      .in("product_id", productIds);
    const stockById = new Map(
      (stockRows ?? []).map((s) => [s.product_id, s.quantity as number]),
    );

    // Online stock cap: unlike the real-stock check above, this IS a hard
    // block — it's a number the owner deliberately set aside for online
    // sales, not a value that can be stale from sync lag.
    const cappedIds = (products ?? [])
      .filter((p) => p.online_stock_limit != null)
      .map((p) => p.id as string);
    const orderedByProduct = await sumOrderedByProduct(
      admin,
      sf.shop_id,
      cappedIds,
    );

    let outOfStockProductId: string | null = null;
    const lines = rawLines.map((l) => {
      const product = byId.get(`${l.product_id ?? ""}`.trim());
      if (!product) return null;
      const qty = Number(l.qty);
      const available = stockById.get(product.id) ?? 0;
      if (product.online_stock_limit != null) {
        const remaining = (product.online_stock_limit as number) -
          (orderedByProduct.get(product.id) ?? 0);
        if (qty > remaining) outOfStockProductId = product.id;
      }
      return {
        productId: product.id as string,
        name: product.name as string,
        price: product.sale_price as number,
        qty,
        lowStock: qty > available,
      };
    });
    if (lines.some((l) => l === null)) {
      return json({ error: "invalid_product" }, 400);
    }
    if (outOfStockProductId) {
      return json({ error: "out_of_stock", product_id: outOfStockProductId }, 409);
    }
    const validLines = lines as {
      productId: string;
      name: string;
      price: number;
      qty: number;
      lowStock: boolean;
    }[];

    const itemsTotal = validLines.reduce((s, l) => s + l.price * l.qty, 0);
    const orderId = crypto.randomUUID();
    const now = new Date().toISOString();
    // Derived from the order's own (guaranteed-unique) id rather than a
    // millisecond timestamp — two orders submitted in the same millisecond
    // (well within the 5-per-10-min rate limit across multiple concurrent
    // shops) previously could have collided on order_no.
    const orderNo = "WEB-" + orderId.replace(/-/g, "").slice(0, 8).toUpperCase();

    const { error: oErr } = await admin.from("orders").insert({
      id: orderId,
      shop_id: sf.shop_id,
      order_no: orderNo,
      channel: "storefront",
      status: "new",
      customer_name: name,
      customer_phone: phone || null,
      delivery_address: (body.address ?? "").trim() || null,
      township: (body.township ?? "").trim() || null,
      items_total: itemsTotal,
      payment_status: "unpaid",
      payment_method: paymentMethod,
      note: (body.note ?? "").trim() || null,
      payment_proof_path: proofPath,
      created_at: now,
      updated_at: now,
    });
    if (oErr) return json({ error: "server_error", detail: oErr.message }, 500);

    const items = validLines.map((l) => ({
      id: crypto.randomUUID(),
      shop_id: sf.shop_id,
      order_id: orderId,
      product_id: l.productId,
      name_snapshot: l.name,
      price_snapshot: l.price,
      qty: l.qty,
      line_total: l.price * l.qty,
      low_stock_at_order: l.lowStock,
      created_at: now,
      updated_at: now,
    }));
    const { error: iErr } = await admin.from("order_items").insert(items);
    if (iErr) {
      // Compensating rollback: the two inserts aren't in a single DB
      // transaction (this client has no RPC for that), so if the items
      // insert fails after the order insert already succeeded, delete the
      // now-orphaned order rather than leaving a real order with
      // items_total set and zero line items visible in the shop's Orders
      // list.
      const { error: delErr } = await admin.from("orders").delete().eq(
        "id",
        orderId,
      );
      if (delErr) {
        // Nothing further to compensate with from here — surface it in the
        // function logs so an orphaned order (real row, zero items) can at
        // least be found and cleaned up manually instead of vanishing
        // silently.
        console.error(
          `submit_order: failed to roll back orphaned order ${orderId} after order_items insert failed`,
          delErr,
        );
      }
      return json({ error: "server_error", detail: iErr.message }, 500);
    }

    return json({ ok: true, order_no: orderNo });
  }

  return json({ error: "bad_action" }, 400);
});
