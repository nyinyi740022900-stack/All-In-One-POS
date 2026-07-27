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
//
// Anti-abuse on submit_order (all silent to a genuine customer, none of them
// block a legitimate order): a hidden honeypot field (`hp`) catches
// blind-filling bots; at most 5 attempts per (shop, IP) per 10 minutes
// (`storefront_order_attempts`); a phone on the owner's block-list
// (`storefront_blocklist`) is rejected outright; a line that asks for more
// than the shop's recorded stock is still accepted but flagged on
// `order_items.low_stock_at_order` for the owner to notice before packing.
//
// Deploy: supabase functions deploy storefront

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// deno-lint-ignore no-explicit-any
function json(body: any, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return json({});
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceKey);

  // deno-lint-ignore no-explicit-any
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const action = body.action as string;
  const slug = (body.slug ?? "").trim();
  if (!slug) return json({ error: "bad_request" }, 400);

  const { data: sf } = await admin
    .from("storefronts")
    .select("*")
    .eq("slug", slug)
    .eq("enabled", true)
    .maybeSingle();
  if (!sf) return json({ error: "not_found" }, 404);

  if (action === "catalog") {
    const { data: products, error } = await admin
      .from("products")
      .select("id, name, sale_price, unit, image_url")
      .eq("shop_id", sf.shop_id)
      .eq("is_active", true)
      .eq("is_deleted", false)
      .order("name");
    if (error) return json({ error: "server_error" }, 500);
    return json({
      storefront: {
        display_name: sf.display_name,
        phone: sf.phone,
        address: sf.address,
        pay_kpay: sf.pay_kpay,
        pay_kpay_name: sf.pay_kpay_name,
        pay_wave: sf.pay_wave,
        pay_wave_name: sf.pay_wave_name,
        logo_url: sf.logo_url,
      },
      products,
    });
  }

  if (action === "submit_order") {
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
      .select("id, name, sale_price")
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

    const lines = rawLines.map((l) => {
      const product = byId.get(`${l.product_id ?? ""}`.trim());
      if (!product) return null;
      const qty = Number(l.qty);
      const available = stockById.get(product.id) ?? 0;
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
    const orderNo = "WEB-" + Date.now().toString().slice(-8);

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
      payment_proof_path: (body.payment_proof_path ?? "").trim() || null,
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
    if (iErr) return json({ error: "server_error", detail: iErr.message }, 500);

    return json({ ok: true, order_no: orderNo });
  }

  return json({ error: "bad_action" }, 400);
});
