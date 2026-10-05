// Edge Function: public B2B2C storefront.
//
// Anonymous customers browse a shop's published catalog and place guest orders.
// The client only ever has the anon key; this function uses the service role
// internally so it can read products / write orders across shop-isolation RLS,
// while exposing ONLY safe fields (never secrets, never other shops' data).
//
// Actions:
//   catalog       { slug }  -> { storefront, products, categories }
//                    products only include rows with `sell_online = true`
//                    (owner-controlled per-product toggle, migration 0084 —
//                    a product can be sold in-store but hidden from this
//                    public catalog; defaults true so nothing changed for
//                    any shop until an owner explicitly flips one off).
//   submit_order  { slug, customer_name, phone, address, township, note,
//                    payment_method ('transfer'|'cod'), payment_proof_path,
//                    lines[], hp } -> { ok, order_no, items_total, lines[] }
//   list_billing_shops {} -> { shops[], card_payment } (authenticated owner)
//   submit_license_request { shop_id, client_request_id, plan, method,
//                    ref_no, phone?, payment_proof_path? } -> request receipt
//                    Server selects price/duration; owner membership is required.
//   my_requests { shop_id } -> { requests[] } (authenticated owner)
//   create_checkout { shop_id, plan } -> { url } (authenticated owner)
//   GET ?action=og&slug=… -> HTML Open Graph card (Facebook/Viber crawlers)
//
// Anti-abuse on submit_order: a hidden honeypot field (`hp`) catches
// blind-filling bots; at most 5 attempts per (shop, IP) per 10 minutes
// (`storefront_order_attempts`); an IP on the owner's block-list
// (`storefront_blocklist`) is rejected outright (403 `blocked`). Two
// different stock checks: a line over the shop's real recorded stock is
// still accepted, just flagged on `order_items.low_stock_at_order` for the
// owner to notice before packing (real stock can lag synced reality); a line
// over a product's owner-set `online_stock_limit` (a deliberate cap,
// independent of real stock, e.g. reserving only some units for online) IS
// hard-rejected (409 `out_of_stock`) — see `sumOrderedByProduct` (pending/
// active orders only; delivered and cancelled do not consume the cap).
// Opening hours (Asia/Yangon) and require_transfer_proof: see migration 0053.
//
// Deploy: supabase functions deploy storefront

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  gatewayAvailable,
  gatewayTestMode,
  verifyVariantForPlan,
} from "../_shared/gateway_mode.ts";

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

function clientIp(req: Request): string {
  const fromXff = normalizeIp(req.headers.get("x-forwarded-for") ?? "");
  if (fromXff) return fromXff;
  return normalizeIp(req.headers.get("x-real-ip") ?? "");
}

function validIpv4(ip: string): boolean {
  const parts = ip.split(".");
  if (parts.length !== 4) return false;
  for (const p of parts) {
    const n = Number(p);
    if (!Number.isInteger(n) || n < 0 || n > 255) return false;
    if (p.length > 1 && p.startsWith("0")) return false;
  }
  return true;
}

/** Eight 16-bit groups, or null if `s` is not a valid IPv6 textual form. */
function parseIpv6Groups(s: string): number[] | null {
  if (!s || s.includes(":::")) return null;
  let head = s;
  let dotted: string | null = null;
  if (s.includes(".")) {
    const embedded = s.match(/^(.*):(\d{1,3}(?:\.\d{1,3}){3})$/);
    if (!embedded) return null;
    head = embedded[1];
    dotted = embedded[2];
    if (head === ":") head = "::";
    if (!validIpv4(dotted)) return null;
  }
  const prefix = parseIpv6N(head, dotted == null ? 8 : 6);
  if (!prefix) return null;
  if (dotted == null) return prefix;
  const o = dotted.split(".").map(Number);
  return [...prefix, (o[0] << 8) | o[1], (o[2] << 8) | o[3]];
}

function parseIpv6N(s: string, n: number): number[] | null {
  const sides = s.split("::");
  if (sides.length > 2) return null;
  const parseSide = (side: string): number[] | null => {
    if (!side) return [];
    const parts = side.split(":");
    const out: number[] = [];
    for (const p of parts) {
      if (!p || p.length > 4 || !/^[0-9a-f]+$/.test(p)) return null;
      out.push(parseInt(p, 16));
    }
    return out;
  };
  if (sides.length === 1) {
    const g = parseSide(s);
    if (g == null || g.length !== n) return null;
    return g;
  }
  const left = parseSide(sides[0]);
  const right = parseSide(sides[1]);
  if (left == null || right == null) return null;
  const missing = n - left.length - right.length;
  if (missing < 1) return null;
  return [...left, ...Array(missing).fill(0), ...right];
}

function ipv4FromIpv6(g: number[]): string | null {
  if (g.length !== 8) return null;
  if (g[0] !== 0 || g[1] !== 0 || g[2] !== 0 || g[3] !== 0 || g[4] !== 0) {
    return null;
  }
  const mapped = g[5] === 0xffff;
  const compatible = g[5] === 0;
  if (!mapped && !compatible) return null;
  if (compatible && g[6] === 0 && g[7] <= 1) return null;
  const a = (g[6] >> 8) & 0xff;
  const b = g[6] & 0xff;
  const c = (g[7] >> 8) & 0xff;
  const d = g[7] & 0xff;
  return `${a}.${b}.${c}.${d}`;
}

/** RFC 5952: lowercase hex, no leading zeros, `::` for the longest zero run. */
function canonicalIpv6(g: number[]): string {
  let bestStart = -1;
  let bestLen = 0;
  let i = 0;
  while (i < 8) {
    if (g[i] !== 0) {
      i++;
      continue;
    }
    let j = i;
    while (j < 8 && g[j] === 0) j++;
    const len = j - i;
    if (len > bestLen) {
      bestStart = i;
      bestLen = len;
    }
    i = j;
  }
  const hex = (n: number) => n.toString(16);
  if (bestLen < 2) return g.map(hex).join(":");
  const left = g.slice(0, bestStart).map(hex).join(":");
  const right = g.slice(bestStart + bestLen).map(hex).join(":");
  if (!left) return "::" + right;
  if (!right) return left + "::";
  return left + "::" + right;
}

/// Canonical client IP for block-list matching. Must stay in lockstep with
/// Dart `normalizeStorefrontIp`. Uses only the last X-Forwarded-For hop
/// (trusted-proxy count 1). Does not walk left into client-supplied hops.
function normalizeIp(raw: string): string {
  const hops = raw.split(",").map((s) => s.trim()).filter(Boolean);
  if (hops.length === 0) return "";
  const n = normalizeOneHop(hops[hops.length - 1]);
  if (!n || isNonPublicIp(n)) return "";
  return n;
}

function normalizeOneHop(raw: string): string {
  let v = raw.trim().toLowerCase();
  if (!v || v === "unknown" || v === "null") return "";
  const bracket = v.match(/^\[([0-9a-f:.]+)\](?::\d+)?$/);
  if (bracket) v = bracket[1];
  const v4 = v.match(/^(\d{1,3}(?:\.\d{1,3}){3})(?::\d+)?$/);
  if (v4) {
    const ip = v4[1];
    if (!validIpv4(ip)) return "";
    if (ip === "0.0.0.0" || ip.startsWith("127.")) return "";
    return ip;
  }
  const groups = parseIpv6Groups(v);
  if (!groups) return "";
  if (groups.every((n) => n === 0)) return "";
  if (
    groups[0] === 0 &&
    groups[1] === 0 &&
    groups[2] === 0 &&
    groups[3] === 0 &&
    groups[4] === 0 &&
    groups[5] === 0 &&
    groups[6] === 0 &&
    groups[7] === 1
  ) {
    return "";
  }
  const mappedV4 = ipv4FromIpv6(groups);
  if (mappedV4) {
    if (!validIpv4(mappedV4)) return "";
    if (mappedV4 === "0.0.0.0" || mappedV4.startsWith("127.")) return "";
    return mappedV4;
  }
  return canonicalIpv6(groups);
}

function isNonPublicIp(ip: string): boolean {
  if (ip.includes(".")) return isNonPublicIpv4(ip);
  return isNonPublicIpv6(ip);
}

function isNonPublicIpv4(ip: string): boolean {
  const p = ip.split(".").map(Number);
  if (p.length !== 4) return true;
  const a = p[0];
  const b = p[1];
  if (a === 10) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 169 && b === 254) return true;
  return false;
}

function isNonPublicIpv6(ip: string): boolean {
  const g = parseIpv6Groups(ip);
  if (!g || g.length !== 8) return true;
  if ((g[0] & 0xffc0) === 0xfe80) return true;
  if ((g[0] & 0xfe00) === 0xfc00) return true;
  return false;
}

/// True when [proofPath] is a real object in the private `payment-proofs`
/// bucket. Prefix-only checks are not enough — a crafted path that never
/// uploaded would still attach to the order. List first (no bytes); download
/// if list is inconclusive so a just-uploaded object still counts.
async function paymentProofExists(
  admin: Admin,
  proofPath: string,
): Promise<boolean> {
  const slash = proofPath.lastIndexOf("/");
  if (slash <= 0) return false;
  const folder = proofPath.slice(0, slash);
  const name = proofPath.slice(slash + 1);
  if (!name) return false;
  const { data, error } = await admin.storage
    .from("payment-proofs")
    .list(folder, { limit: 20, search: name });
  if (!error && (data ?? []).some((o: { name: string }) => o.name === name)) {
    return true;
  }
  const { data: blob, error: dlErr } = await admin.storage
    .from("payment-proofs")
    .download(proofPath);
  return !dlErr && blob != null;
}

async function deleteOrderAndItems(
  admin: Admin,
  orderId: string,
): Promise<void> {
  const { error: itemsErr } = await admin
    .from("order_items")
    .delete()
    .eq("order_id", orderId);
  if (itemsErr) {
    console.error(
      `submit_order: failed to delete items for ${orderId}`,
      itemsErr,
    );
  }
  const { error: orderErr } = await admin.from("orders").delete().eq(
    "id",
    orderId,
  );
  if (orderErr) {
    console.error(
      `submit_order: failed to roll back order ${orderId}`,
      orderErr,
    );
  }
}

/// For products that have an `online_stock_limit` set, sums how many units
/// are already spoken for by this shop's existing, pending/active storefront
/// orders — cancelled AND delivered are excluded (delivered has already been
/// fulfilled / converted, so it must not keep consuming the online cap).
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
    .neq("status", "cancelled")
    .neq("status", "delivered");
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

/// Total quantity ordered for one product across every active storefront
/// order created at or before [throughCreatedAt] — used by submit_order's
/// post-insert cap recheck so two orders racing for the last unit resolve
/// consistently: the earlier order's own recheck only counts orders up to
/// (and including) itself, while the later one's recheck also counts the
/// earlier one — so only the later order can ever see itself go over cap.
async function cumulativeOrderedThrough(
  admin: Admin,
  shopId: string,
  productId: string,
  throughCreatedAt: string,
): Promise<number> {
  const { data: activeOrders } = await admin
    .from("orders")
    .select("id")
    .eq("shop_id", shopId)
    .eq("channel", "storefront")
    .eq("is_deleted", false)
    .neq("status", "cancelled")
    .neq("status", "delivered")
    .lte("created_at", throughCreatedAt);
  const orderIds = (activeOrders ?? []).map((o: { id: string }) => o.id);
  if (orderIds.length === 0) return 0;
  const { data: rows } = await admin
    .from("order_items")
    .select("qty")
    .eq("product_id", productId)
    .in("order_id", orderIds)
    .eq("is_deleted", false);
  return (rows ?? []).reduce(
    (sum: number, r: { qty: number }) => sum + (r.qty as number),
    0,
  );
}

// Billing always authenticates the real owner before resolving a shop.
async function billingOwner(admin: Admin, req: Request) {
  const token = (req.headers.get("authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user || data.user.is_anonymous) return null;
  if (data.user.app_metadata?.role !== "owner") return null;
  return data.user;
}

async function billingShops(
  admin: Admin,
  user: { id: string },
): Promise<
  Array<{ shop_id: string; name?: string; plan: string; expires_at: string }>
> {
  const { data, error } = await admin.from("shop_subscriptions")
    .select("shop_id, shop_name, plan, expires_at").eq("owner_user_id", user.id)
    .eq("is_archived", false);
  if (error) throw error;
  return (data ?? []).map((
    s: {
      shop_id: string;
      shop_name?: string;
      plan: string;
      expires_at: string;
    },
  ) => ({ ...s, name: s.shop_name || s.shop_id }));
}

async function handleSubmitLicenseRequest(
  admin: Admin,
  body: Record<string, unknown>,
  req: Request,
): Promise<Response> {
  const owner = await billingOwner(admin, req);
  if (!owner) return json({ error: "not_authenticated" }, 401);
  const shopId = `${body.shop_id ?? ""}`.trim();
  const shops = await billingShops(admin, owner);
  const shop = shops.find((s) => s.shop_id === shopId);
  if (!shop) return json({ error: "forbidden" }, 403);
  const requestId = `${body.client_request_id ?? ""}`;
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(requestId)
  ) return json({ error: "request_id_required" }, 400);
  const plan = body.plan;
  if (plan !== "monthly" && plan !== "yearly") {
    return json({ error: "bad_plan" }, 400);
  }
  const months = plan === "yearly" ? 12 : 1;
  const amount = plan === "yearly" ? 200000 : 20000;
  const method = body.method;
  const refNo = `${body.ref_no ?? ""}`.trim();
  if (!/^\d{6}$/.test(refNo) || (method !== "kbzpay" && method !== "wavepay")) {
    return json({ error: "bad_request" }, 400);
  }
  const proofPath = `${body.payment_proof_path ?? ""}`.trim() || null;
  if (proofPath && !proofPath.startsWith(`_admin/${owner.id}/`)) {
    return json({ error: "bad_proof_path" }, 400);
  }
  const { data: existing, error: readError } = await admin.from(
    "license_requests",
  )
    .select("id, invoice_no, owner_user_id, shop_id").eq("id", requestId)
    .maybeSingle();
  if (readError) return json({ error: "server_error" }, 500);
  if (existing) {
    if (existing.owner_user_id !== owner.id || existing.shop_id !== shopId) {
      return json({ error: "request_id_conflict" }, 409);
    }
    return json({
      ok: true,
      duplicate: true,
      request_id: existing.id,
      invoice_no: existing.invoice_no,
    });
  }
  const ip = clientIp(req);
  if (!ip) return json({ error: "rate_limited" }, 429);
  const { count, error: countError } = await admin.from(
    "license_request_attempts",
  ).select("id", { count: "exact", head: true })
    .eq("ip", ip).gte(
      "created_at",
      new Date(Date.now() - 600000).toISOString(),
    );
  if (countError) return json({ error: "server_error" }, 500);
  if ((count ?? 0) >= 5) return json({ error: "rate_limited" }, 429);
  await admin.from("license_request_attempts").insert({ ip });
  const invoiceNo = "INV-" +
    requestId.replace(/-/g, "").slice(0, 8).toUpperCase();
  const { error } = await admin.from("license_requests").insert({
    id: requestId,
    invoice_no: invoiceNo,
    shop_id: shopId,
    owner_user_id: owner.id,
    shop_name: shop.name,
    device_id: "",
    tier: "online",
    plan,
    months,
    amount,
    method,
    ref_no: refNo,
    phone: `${body.phone ?? ""}`.trim() || null,
    payment_proof_path: proofPath,
    status: "pending",
  });
  if (error?.code === "23505") {
    const { data: raced } = await admin.from("license_requests").select(
      "id, invoice_no, owner_user_id, shop_id",
    )
      .eq("id", requestId).maybeSingle();
    if (raced?.owner_user_id === owner.id && raced?.shop_id === shopId) {
      return json({
        ok: true,
        duplicate: true,
        request_id: raced.id,
        invoice_no: raced.invoice_no,
      });
    }
    return json({ error: "request_id_conflict" }, 409);
  }
  if (error) return json({ error: "server_error" }, 500);
  return json({ ok: true, request_id: requestId, invoice_no: invoiceNo });
}

// The checkout binding is created only after ownership verification. A webhook
// cannot grant time using customer-editable shop/device custom fields.
async function handleCheckout(
  admin: Admin,
  body: Record<string, unknown>,
  req: Request,
) {
  const owner = await billingOwner(admin, req);
  if (!owner) return json({ error: "not_authenticated" }, 401);
  const shops = await billingShops(admin, owner);
  const shopId = `${body.shop_id ?? ""}`;
  if (!shops.some((s) => s.shop_id === shopId)) {
    return json({ error: "forbidden" }, 403);
  }
  if (body.plan !== "monthly" && body.plan !== "yearly") {
    return json({ error: "bad_plan" }, 400);
  }
  const apiKey = Deno.env.get("LEMONSQUEEZY_API_KEY");
  const storeId = Deno.env.get("LEMONSQUEEZY_STORE_ID");
  if (!apiKey || !storeId) return json({ error: "checkout_unavailable" }, 503);
  // The server decides the mode; the client body never does. A test-mode flag
  // on production throws rather than charging play money for real time.
  let testMode: boolean;
  try {
    testMode = gatewayTestMode();
  } catch {
    return json({ error: "checkout_unavailable" }, 503);
  }
  const configKey = `pay.lemonsqueezy.variant_${body.plan}`;
  const { data: cfg } = await admin.from("app_config").select("value").eq(
    "key",
    configKey,
  ).maybeSingle();
  const variantId = `${cfg?.value ?? ""}`;
  // The term comes from the variant the processor will actually charge, not
  // from the plan the client asked for: a `variant_yearly` row pointing at the
  // monthly variant would otherwise sell a year for one month's price.
  const verified = await verifyVariantForPlan(
    apiKey,
    storeId,
    variantId,
    body.plan,
    testMode,
  );
  if ("error" in verified) {
    return json(
      { error: "checkout_unavailable" },
      verified.error === "processor_unavailable" ? 502 : 503,
    );
  }
  // A database lock makes two tabs/devices share one reservation. A client
  // spinner or an in-memory check cannot stop simultaneous function instances.
  let reservation;
  for (let attempt = 0; attempt < 2; attempt++) {
    const { data, error } = await admin.rpc("reserve_gateway_checkout", {
      p_shop_id: shopId,
      p_owner_user_id: owner.id,
      p_variant_id: verified.variantId,
      p_months: verified.months,
    });
    if (error || !data) return json({ error: "checkout_unavailable" }, 503);
    if (data.error || !data.checkout) {
      return json({ error: "checkout_in_progress" }, 409);
    }
    reservation = data.checkout;
    if (data.reserved) break;
    if (reservation.subscription_id) {
      let subscription;
      try {
        const response = await fetch(
          `https://api.lemonsqueezy.com/v1/subscriptions/${
            encodeURIComponent(reservation.subscription_id)
          }`,
          {
            headers: {
              Authorization: `Bearer ${apiKey}`,
              Accept: "application/vnd.api+json",
            },
            signal: AbortSignal.timeout(15000),
          },
        );
        if (!response.ok) return json({ error: "checkout_unavailable" }, 503);
        subscription = (await response.json())?.data?.attributes;
      } catch {
        return json({ error: "checkout_unavailable" }, 503);
      }
      if (
        `${subscription?.store_id}` !== storeId ||
        subscription?.test_mode !== testMode
      ) {
        return json({ error: "checkout_unavailable" }, 503);
      }
      // Cancelled/past_due/unpaid/paused can still be resumed or billed. Only
      // the processor's terminal expired state permits a fresh subscription.
      if (subscription.status === "expired" && attempt === 0) {
        const { error } = await admin.rpc("close_gateway_checkout", {
          p_checkout_id: reservation.id,
          p_subscription_id: reservation.subscription_id,
        });
        if (error) return json({ error: "checkout_unavailable" }, 503);
        continue;
      }
      const portal = subscription.urls?.customer_portal;
      const managementUrl = typeof portal === "string" &&
          /^https:\/\/[^/]+\.lemonsqueezy\.com\//.test(portal)
        ? portal
        : null;
      return json({
        error: "subscription_already_exists",
        management_url: managementUrl,
      }, 409);
    }
    // Never hand an issued URL to another tab: hosted checkout links can
    // produce a fresh payable cart even when it is the same URL. The first
    // tab finishes payment; a lost/expired checkout needs reconciliation,
    // since an invoice may have been paid but its webhook still be delayed.
    return json({ error: "checkout_in_progress" }, 409);
  }
  const id = reservation.id;
  let result: Response;
  try {
    result = await fetch("https://api.lemonsqueezy.com/v1/checkouts", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        Accept: "application/vnd.api+json",
        "Content-Type": "application/vnd.api+json",
      },
      signal: AbortSignal.timeout(15000),
      body: JSON.stringify({
        data: {
          type: "checkouts",
          attributes: {
            checkout_data: { email: owner.email, custom: { billing_id: id } },
            checkout_options: { skip_trial: true },
            // Stated outright, so a key belonging to the other mode fails here
            // rather than after the customer has paid.
            test_mode: testMode,
            product_options: {
              enabled_variants: [Number(verified.variantId)],
              // Back to the page they started from. Cosmetic only: returning
              // here grants nothing, the signed webhook does, and the app picks
              // the new term up on its next receipt refresh.
              redirect_url: "https://shop.allinonepos.app/renew",
            },
            expires_at: reservation.checkout_expires_at,
          },
          relationships: {
            store: { data: { type: "stores", id: storeId } },
            variant: { data: { type: "variants", id: verified.variantId } },
          },
        },
      }),
    });
  } catch {
    // An unknown processor outcome keeps the reservation: retrying a POST
    // could leave two payable URLs with the same shop binding.
    return json({ error: "checkout_unavailable" }, 502);
  }
  if (!result.ok) {
    if (result.status >= 400 && result.status < 500) {
      await admin.rpc("close_gateway_checkout", {
        p_checkout_id: id,
        p_subscription_id: null,
      });
    }
    return json({ error: "checkout_unavailable" }, 502);
  }
  let resultBody;
  try {
    resultBody = await result.json();
  } catch {
    return json({ error: "checkout_unavailable" }, 502);
  }
  const url = resultBody?.data?.attributes?.url;
  if (typeof url !== "string" || !url.startsWith("https://")) {
    return json({ error: "checkout_unavailable" }, 502);
  }
  const { error: saveError } = await admin.from("billing_checkouts")
    .update({ checkout_url: url }).eq("id", id);
  if (saveError) return json({ error: "checkout_unavailable" }, 503);
  return json({ url });
}

/// Opaque request-id receipt. Never returns keys, payment proof paths or
/// account contact details. Billing history remains owner authenticated.
async function handleReceipt(
  admin: Admin,
  // deno-lint-ignore no-explicit-any
  body: any,
  req: Request,
): Promise<Response> {
  // Same IP budget as the other public entry points. Guessing a UUID is
  // infeasible, but this stops anyone turning the endpoint into a probe.
  const ip = clientIp(req);
  if (!ip) return json({ error: "rate_limited" }, 429);
  const windowStart = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { count } = await admin
    .from("license_request_attempts")
    .select("id", { count: "exact", head: true })
    .eq("ip", ip)
    .gte("created_at", windowStart);
  if ((count ?? 0) >= 30) {
    return json({ error: "rate_limited" }, 429);
  }
  // Was checking this table's count without ever recording its own calls
  // into it (unlike submit_license_request, which does) — every past
  // receipt call was invisible to the very limit it was enforcing, so the
  // 30-per-10-min cap never actually engaged for repeated receipt calls.
  await admin.from("license_request_attempts").insert({ ip });

  const requestId = `${body.request_id ?? ""}`.trim();
  if (!requestId) return json({ error: "bad_request" }, 400);

  const { data: row } = await admin
    .from("license_requests")
    .select(
      "id, invoice_no, shop_name, plan, months, amount, method, " +
        "ref_no, status, payment_status, fulfilled_expires_at, reject_reason, " +
        "mmpay_expires_at, paid_at, created_at, updated_at",
    )
    .eq("id", requestId)
    .maybeSingle();
  if (!row) return json({ error: "not_found" }, 404);

  // The key is the payout of this whole flow — hand it over only once the
  // request is actually fulfilled, never while it is pending or rejected.

  return json({
    receipt: {
      invoice_no: row.invoice_no,
      shop_name: row.shop_name,
      // Enough to recognise your own device without printing the whole id.

      plan: row.plan,
      months: row.months,
      amount: row.amount,
      method: row.method,
      ref_no: row.ref_no,
      status: row.status,
      payment_status: row.payment_status,
      expires_at: row.fulfilled_expires_at,
      reject_reason: row.status === "rejected" ? row.reject_reason : null,
      mmpay_expires_at: row.mmpay_expires_at,
      paid_at: row.paid_at,
      created_at: row.created_at,
      updated_at: row.updated_at,
    },
  });
}

/// The last 20 renewal requests for the signed-in shop — same safe-field
/// selection as [handleReceipt] (never `payment_proof_path`/phone/email),
/// scoped by `app_metadata.shop_id` off the caller's own JWT rather than an
/// RLS policy, so `license_requests` stays service-role-only end to end
/// (see 0069's "don't open this table to anon" note — this handler never
/// grants anon or cross-shop access, only "the shop I already am").
async function handleMyRequests(
  admin: Admin,
  req: Request,
  body: Record<string, unknown>,
): Promise<Response> {
  const owner = await billingOwner(admin, req);
  if (!owner) return json({ error: "not_authenticated" }, 401);
  const shops = await billingShops(admin, owner);
  const shopId = `${body.shop_id ?? ""}`;
  if (!shops.some((s) => s.shop_id === shopId)) {
    return json({ error: "forbidden" }, 403);
  }
  const { data, error } = await admin.from("license_requests")
    .select(
      "id, invoice_no, plan, months, amount, method, status, payment_status, created_at",
    )
    .eq("shop_id", shopId).order("created_at", { ascending: false }).limit(20);
  return error
    ? json({ error: "server_error" }, 500)
    : json({ requests: data ?? [] });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return json({});

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceKey);
  const shopWebBase = "https://shop.allinonepos.app";

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

  if (action === "submit_license_request") {
    return handleSubmitLicenseRequest(admin, body, req);
  }

  // Also slug-less: a receipt is addressed by its own request id, not by a
  // shop (the shop may not even exist yet when the request was submitted).
  if (action === "receipt") {
    return handleReceipt(admin, body, req);
  }

  if (action === "my_requests") {
    return handleMyRequests(admin, req, body);
  }

  if (action === "list_billing_shops") {
    const owner = await billingOwner(admin, req);
    if (!owner) return json({ error: "not_authenticated" }, 401);
    // `card_payment` tells the renewal page whether to offer the international
    // card option at all, so it never shows a button that cannot work. The
    // server owns that answer: the page has no access to the processor secrets.
    return json({
      shops: await billingShops(admin, owner),
      card_payment: gatewayAvailable(),
    });
  }
  if (action === "create_checkout") return handleCheckout(admin, body, req);

  const slug = (body.slug ?? "").trim();
  if (!slug) return json({ error: "bad_request" }, 400);

  // Column-explicit rather than `*`. Nothing leaked today — the reply below
  // is built field by field, never spread from `sf` — but this is the one
  // unauthenticated function in the system, and `*` means the next column
  // added to `storefronts` arrives here automatically and is one careless
  // `...sf` away from being public. Listing them makes adding a column a
  // decision instead of a default.
  const { data: sf } = await admin
    .from("storefronts")
    // deno-fmt-ignore — one unbroken literal on purpose: supabase-js infers
    // the row type by parsing this string, and splitting it across a `+`
    // degrades every field to GenericStringError.
    .select(
      "shop_id, display_name, phone, address, logo_url, payment_methods, currency_code, enabled, hours_enabled, open_minute, close_minute, require_transfer_proof",
    )
    .eq("slug", slug)
    .eq("enabled", true)
    .maybeSingle();
  if (!sf) return json({ error: "not_found" }, 404);

  const { data: subscription } = await admin.from("shop_subscriptions")
    .select("plan, expires_at, is_archived").eq("shop_id", sf.shop_id)
    .maybeSingle();
  const premium = subscription && !subscription.is_archived &&
    ["trial", "monthly", "yearly", "premium"].includes(subscription.plan) &&
    Date.parse(subscription.expires_at) + 14 * 86400000 > Date.now();
  const acceptingOrders = !!premium && isWithinHours(
    sf.hours_enabled === true,
    sf.open_minute as number | null,
    sf.close_minute as number | null,
  );

  if (action === "catalog") {
    const { data: products, error } = await admin
      .from("products")
      .select(
        "id, name, sale_price, unit, image_url, online_stock_limit, category_id",
      )
      .eq("shop_id", sf.shop_id)
      .eq("is_active", true)
      .eq("is_deleted", false)
      .eq("sell_online", true)
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

    // Categories the storefront can filter by — only ones actually in use by
    // a published product (an empty/unused category list would just be a
    // filter row of chips with nothing behind them). `category_id` has no DB
    // foreign key (see 0001_init.sql), so this is a plain in-memory join
    // rather than a Postgrest embedded-resource select.
    const usedCategoryIds = new Set(
      (products ?? [])
        .map((p) => p.category_id as string | null)
        .filter((id): id is string => !!id),
    );
    let categoriesOut: { id: string; name: string }[] = [];
    if (usedCategoryIds.size > 0) {
      const { data: categories } = await admin
        .from("categories")
        .select("id, name, sort")
        .eq("shop_id", sf.shop_id)
        .eq("is_deleted", false)
        .order("sort");
      categoriesOut = (categories ?? [])
        .filter((c) => usedCategoryIds.has(c.id as string))
        .map((c) => ({ id: c.id as string, name: c.name as string }));
    }

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
        payment_methods: sf.payment_methods ?? [],
        logo_url: sf.logo_url,
        currency_code: sf.currency_code ?? "MMK",
        accepting_orders: acceptingOrders,
        hours_enabled: sf.hours_enabled === true,
        open_minute: sf.open_minute ?? null,
        close_minute: sf.close_minute ?? null,
        require_transfer_proof: sf.require_transfer_proof !== false,
      },
      products: productsOut,
      categories: categoriesOut,
    });
  }

  if (action === "submit_order") {
    if (!premium) return json({ error: "subscription_lapsed" }, 403);
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
    const ip = clientIp(req);
    if (!ip) {
      // No public client IP: do not share an "unknown" bucket (that would
      // rate-limit every header-less caller together, and would let a
      // spoofed leftmost hop skip a real block). Fail closed.
      return json({ error: "rate_limited" }, 429);
    }
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

    // Block-list: an IP the owner has blocked (usually after a scam/spam
    // order) can't place a new one. `ip` is already the last XFF hop.
    const { data: blockedRows } = await admin
      .from("storefront_blocklist")
      .select("ip")
      .eq("shop_id", sf.shop_id)
      .eq("ip", ip)
      .limit(1);
    if ((blockedRows ?? []).length > 0) {
      return json({ error: "blocked" }, 403);
    }

    // 'transfer' (KPay/Wave, usually with a screenshot) or 'cod' (cash on
    // delivery) — anything else collapses to null (unspecified).
    const rawMethod = `${body.payment_method ?? ""}`.trim();
    const paymentMethod = rawMethod === "transfer" || rawMethod === "cod"
      ? rawMethod
      : null;

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
    if (proofPath && !(await paymentProofExists(admin, proofPath))) {
      return json({ error: "proof_missing" }, 400);
    }

    // Security: every line must name a real, active product belonging to
    // THIS shop, with a sane positive quantity. Price/name are never taken
    // from the client — a browser console can send anything — they're always
    // re-read from the product row so a submitted order can't under-price or
    // free-ride an item. Duplicate lines of the same product are summed
    // before the online-cap compare (and stored as one line) so splitting
    // qty across two rows cannot sneak past remaining.
    const MAX_QTY = 999;
    const qtyByProduct = new Map<string, number>();
    for (const l of rawLines) {
      const id = `${l.product_id ?? ""}`.trim();
      const qty = Number(l.qty);
      if (!id) return json({ error: "bad_request" }, 400);
      if (!Number.isInteger(qty) || qty <= 0 || qty > MAX_QTY) {
        return json({ error: "invalid_quantity" }, 400);
      }
      const next = (qtyByProduct.get(id) ?? 0) + qty;
      if (next > MAX_QTY) return json({ error: "invalid_quantity" }, 400);
      qtyByProduct.set(id, next);
    }
    const productIds = [...qtyByProduct.keys()];
    if (productIds.length === 0) {
      return json({ error: "bad_request" }, 400);
    }

    // sell_online is re-checked here too, not just in `catalog` — a customer's
    // browser can hold an already-fetched catalog for the whole session, so
    // without this an owner toggling a product off mid-session would not
    // actually stop an in-flight order for it. A filtered-out product simply
    // isn't in `byId` below, which already rejects an unknown product id.
    const { data: products, error: pErr } = await admin
      .from("products")
      .select("id, name, sale_price, online_stock_limit")
      .eq("shop_id", sf.shop_id)
      .eq("is_active", true)
      .eq("is_deleted", false)
      .eq("sell_online", true)
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
    // sales, not a value that can be stale from sync lag. Compared against
    // the summed qty per product, not each raw line on its own.
    const cappedIds = (products ?? [])
      .filter((p) => p.online_stock_limit != null)
      .map((p) => p.id as string);
    const orderedByProduct = await sumOrderedByProduct(
      admin,
      sf.shop_id,
      cappedIds,
    );

    let outOfStockProductId: string | null = null;
    const validLines: {
      productId: string;
      name: string;
      price: number;
      qty: number;
      lowStock: boolean;
    }[] = [];
    for (const [productId, qty] of qtyByProduct) {
      const product = byId.get(productId);
      if (!product) return json({ error: "invalid_product" }, 400);
      const available = stockById.get(product.id) ?? 0;
      if (product.online_stock_limit != null) {
        const remaining = (product.online_stock_limit as number) -
          (orderedByProduct.get(product.id) ?? 0);
        if (qty > remaining) outOfStockProductId = product.id as string;
      }
      validLines.push({
        productId: product.id as string,
        name: product.name as string,
        price: product.sale_price as number,
        qty,
        lowStock: qty > available,
      });
    }
    if (outOfStockProductId) {
      return json(
        { error: "out_of_stock", product_id: outOfStockProductId },
        409,
      );
    }

    const itemsTotal = validLines.reduce((s, l) => s + l.price * l.qty, 0);

    // Idempotency: the browser generates the order id and sends it, so a
    // retry after a lost response resolves to the SAME order instead of a
    // second one.
    //
    // This matters because the client bounds each invoke at 15s
    // (kEdgeInvokeTimeout) while this handler does 6+ sequential round
    // trips plus a possible cold start. An order that commits at ~16s looks
    // to the customer like a plain failure — the button re-enables and the
    // message is generic — so they tap Place Order again, and the shop
    // packs and ships two orders for one transfer. Same convention the sync
    // outbox already uses ("every row has a client-generated UUID" —
    // CLAUDE.md); a caller that sends nothing keeps the old behaviour.
    const clientOrderId = `${body.client_order_id ?? ""}`.trim();
    if (clientOrderId) {
      const { data: existing } = await admin
        .from("orders")
        .select("id, order_no, items_total")
        .eq("id", clientOrderId)
        .eq("shop_id", sf.shop_id)
        .maybeSingle();
      if (existing) {
        const { data: prior } = await admin
          .from("order_items")
          .select("product_id, name_snapshot, price_snapshot, qty, line_total")
          .eq("order_id", clientOrderId);
        return json({
          ok: true,
          duplicate: true,
          order_no: existing.order_no,
          items_total: existing.items_total,
          lines: (prior ?? []).map((i) => ({
            product_id: i.product_id,
            name: i.name_snapshot,
            price: i.price_snapshot,
            qty: i.qty,
            line_total: i.line_total,
          })),
        });
      }
    }
    const orderId = clientOrderId || crypto.randomUUID();
    const now = new Date().toISOString();
    // Derived from the order's own (guaranteed-unique) id rather than a
    // millisecond timestamp — two orders submitted in the same millisecond
    // (well within the 5-per-10-min rate limit across multiple concurrent
    // shops) previously could have collided on order_no.
    const orderNo = "WEB-" +
      orderId.replace(/-/g, "").slice(0, 8).toUpperCase();

    const { error: oErr } = await admin.from("orders").insert({
      id: orderId,
      shop_id: sf.shop_id,
      order_no: orderNo,
      channel: "storefront",
      status: "new",
      customer_name: name,
      customer_phone: phone || null,
      customer_ip: ip,
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
      // Compensating rollback: supabase-js has no multi-statement
      // transaction, so if the items insert fails after the order insert
      // already succeeded, delete both rather than leaving a real order
      // with items_total set and zero line items.
      await deleteOrderAndItems(admin, orderId);
      return json({ error: "server_error", detail: iErr.message }, 500);
    }

    // Re-check the online cap after both rows exist. Two concurrent
    // submit_order calls can both pass the pre-insert remaining check for
    // the last unit; whichever commit leaves a product over its cap is
    // rolled back here. (A true SELECT FOR UPDATE would need a Postgres
    // RPC — each REST call is its own transaction.)
    //
    // Ranked by created_at (this order's own `now`, set above), not a flat
    // aggregate: comparing the running total *as of and including this
    // order* against the cap means only the later of two racing orders for
    // the last unit sees itself go over — the earlier one's own recheck
    // stays within cap and survives. Comparing the plain aggregate instead
    // (the previous approach) made BOTH racing orders see the same
    // over-cap total and both self-reject, losing the sale entirely even
    // though exactly one of them should have honored it first-come-first-served.
    if (cappedIds.length > 0) {
      let overProductId: string | null = null;
      for (const p of products ?? []) {
        if (p.online_stock_limit == null) continue;
        if (!cappedIds.includes(p.id as string)) continue;
        const cumulative = await cumulativeOrderedThrough(
          admin,
          sf.shop_id,
          p.id as string,
          now,
        );
        if (cumulative > (p.online_stock_limit as number)) {
          overProductId = p.id as string;
          break;
        }
      }
      if (overProductId) {
        await deleteOrderAndItems(admin, orderId);
        return json({ error: "out_of_stock", product_id: overProductId }, 409);
      }
    }

    return json({
      ok: true,
      order_no: orderNo,
      items_total: itemsTotal,
      lines: validLines.map((l) => ({
        product_id: l.productId,
        name: l.name,
        price: l.price,
        qty: l.qty,
        line_total: l.price * l.qty,
      })),
    });
  }

  return json({ error: "bad_action" }, 400);
});
