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
//   my_requests {} (Authorization: Bearer <user JWT>) -> { requests[] } —
//                    the /renew page's optional sign-in convenience layer;
//                    the signed-in shop's own last 20 renewal requests.
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
  const ip = clientIp(req);
  if (!ip) return json({ error: "rate_limited" }, 429);
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
  // Human-quotable receipt number, derived from the id so it is unique
  // without a sequence and stable forever — the same trick submit_order uses
  // for `order_no`. This is also what we will hand MyanMyanPay as its
  // `orderId` when the gateway lands, so one number reconciles the shop's
  // Viber message, this row, and MMPay's dashboard.
  const invoiceNo = "INV-" +
    requestId.replace(/-/g, "").slice(0, 8).toUpperCase();
  const { error } = await admin.from("license_requests").insert({
    id: requestId,
    invoice_no: invoiceNo,
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
  // Both are known before the insert — return them so the page can render
  // the receipt immediately and hand the owner a link to come back to.
  return json({ ok: true, request_id: requestId, invoice_no: invoiceNo });
}

/// Public receipt for one renewal request, keyed by the request id the
/// submitting browser was handed.
///
/// Why a bare id is enough of a credential: it is a server-generated UUIDv4
/// returned only to that browser, so it cannot be guessed — the same model
/// every order-tracking link uses. And the one sensitive thing it can
/// return, `issued_key`, is device-bound at activation (one device per key),
/// so a leaked link does not hand a stranger a usable licence. What it must
/// never return is the rest of the row: `payment_proof_path` is a photo of
/// somebody's bank app, and phone/email belong to the shop, not to whoever
/// holds the link.
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

  const requestId = `${body.request_id ?? ""}`.trim();
  if (!requestId) return json({ error: "bad_request" }, 400);

  const { data: row } = await admin
    .from("license_requests")
    .select(
      "id, invoice_no, shop_name, device_id, plan, months, amount, method, " +
        "ref_no, status, payment_status, issued_key, reject_reason, " +
        "mmpay_expires_at, paid_at, created_at, updated_at",
    )
    .eq("id", requestId)
    .maybeSingle();
  if (!row) return json({ error: "not_found" }, 404);

  // The key is the payout of this whole flow — hand it over only once the
  // request is actually fulfilled, never while it is pending or rejected.
  const issuedKey = row.status === "fulfilled" ? row.issued_key : null;

  return json({
    receipt: {
      invoice_no: row.invoice_no,
      shop_name: row.shop_name,
      // Enough to recognise your own device without printing the whole id.
      device_id_tail: `${row.device_id ?? ""}`.slice(-6) || null,
      plan: row.plan,
      months: row.months,
      amount: row.amount,
      method: row.method,
      ref_no: row.ref_no,
      status: row.status,
      payment_status: row.payment_status,
      issued_key: issuedKey,
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
  url: string,
  anonKey: string,
  admin: Admin,
  req: Request,
): Promise<Response> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const asUser = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ error: "not_authenticated" }, 401);
  }
  const shopId =
    (userData.user.app_metadata as Record<string, unknown> | null)
      ?.shop_id as string | undefined;
  if (!shopId) return json({ requests: [] });

  const { data, error } = await admin
    .from("license_requests")
    .select(
      "id, invoice_no, plan, months, amount, method, status, payment_status, created_at",
    )
    .eq("shop_id", shopId)
    .order("created_at", { ascending: false })
    .limit(20);
  if (error) return json({ error: "server_error", detail: error.message }, 500);
  return json({ requests: data ?? [] });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return json({});

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
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

  // Dispatched before the slug lookup below: a subscription-renewal request
  // has no shop slug at all (the shop identifies itself only by the
  // device_id it types in) — see handleSubmitLicenseRequest.
  if (action === "submit_license_request") {
    return handleSubmitLicenseRequest(admin, body, req);
  }

  // Also slug-less: a receipt is addressed by its own request id, not by a
  // shop (the shop may not even exist yet when the request was submitted).
  if (action === "receipt") {
    return handleReceipt(admin, body, req);
  }

  // The /renew page's optional sign-in convenience layer: a shop with a
  // Supabase Auth account (created in-app via "Create shop login") can see
  // its own past renewal requests instead of only ever seeing the one it
  // just submitted. Requires a real session — the caller's own access token
  // travels in the Authorization header exactly like any authenticated
  // Postgrest/Function call from the mobile app.
  if (action === "my_requests") {
    return handleMyRequests(url, anonKey, admin, req);
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
      return json({ error: "out_of_stock", product_id: outOfStockProductId }, 409);
    }

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
    if (cappedIds.length > 0) {
      const orderedAfter = await sumOrderedByProduct(
        admin,
        sf.shop_id,
        cappedIds,
      );
      let overProductId: string | null = null;
      for (const p of products ?? []) {
        if (p.online_stock_limit == null) continue;
        if (
          (orderedAfter.get(p.id as string) ?? 0) >
            (p.online_stock_limit as number)
        ) {
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
