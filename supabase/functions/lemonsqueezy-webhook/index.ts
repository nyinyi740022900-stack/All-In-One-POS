// HMAC-authenticated subscription invoices are the single payment authority.
// order_created is deliberately ignored: a subscription's initial payment also
// emits an invoice, and granting both would purchase two terms with one charge.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return cors(new Response(null, { status: 204 }));
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const secret = Deno.env.get("LEMONSQUEEZY_WEBHOOK_SECRET");
  if (!secret) return json({ error: "server_error" }, 500);
  const raw = await req.text();
  if (
    !await verifySignature(raw, req.headers.get("x-signature") ?? "", secret)
  ) return json({ error: "invalid_signature" }, 401);
  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  const event = payload?.meta?.event_name;
  if (event !== "subscription_payment_success") {
    return json({ ok: true, ignored: event });
  }
  const attrs = payload?.data?.attributes ?? {};
  const invoiceId = `${payload?.data?.id ?? ""}`;
  const subscriptionId = `${attrs.subscription_id ?? ""}`;
  if (
    !invoiceId || !/^\d+$/.test(subscriptionId) || attrs.status !== "paid" ||
    attrs.refunded === true
  ) return json({ error: "invalid_payment" }, 400);
  // Live service must never grant a live subscription for a processor test charge.
  if (attrs.test_mode !== false) {
    return json({ error: "test_payment_not_live" }, 400);
  }
  if (!["initial", "renewal"].includes(attrs.billing_reason)) {
    return json({ ok: true, ignored: attrs.billing_reason });
  }
  const storeId = Deno.env.get("LEMONSQUEEZY_STORE_ID");
  const apiKey = Deno.env.get("LEMONSQUEEZY_API_KEY");
  if (!storeId || !apiKey) {
    return json({ error: "gateway_not_configured" }, 503);
  }
  if (`${attrs.store_id}` !== storeId) {
    return json({ error: "wrong_store" }, 403);
  }
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const billingId = `${payload?.meta?.custom_data?.billing_id ?? ""}`;
  let query = admin.from("billing_checkouts").select(
    "id, shop_id, variant_id, months, subscription_id",
  );
  query = billingId
    ? query.eq("id", billingId)
    : query.eq("subscription_id", subscriptionId);
  const { data: checkout, error } = await query.maybeSingle();
  if (error) return json({ error: "server_error" }, 500);
  if (!checkout) return json({ error: "verified_checkout_required" }, 409);
  // Invoice objects do not include a variant. Resolve their signed subscription
  // id through the processor API; never infer duration from a shop's last event.
  const response = await fetch(
    `https://api.lemonsqueezy.com/v1/subscriptions/${
      encodeURIComponent(subscriptionId)
    }`,
    {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        Accept: "application/vnd.api+json",
      },
      signal: AbortSignal.timeout(15000),
    },
  );
  if (!response.ok) return json({ error: "processor_unavailable" }, 502);
  const subscription = (await response.json())?.data?.attributes;
  if (
    `${subscription?.store_id}` !== storeId ||
    subscription?.test_mode !== false ||
    `${subscription?.variant_id}` !== checkout.variant_id
  ) return json({ error: "checkout_variant_mismatch" }, 409);
  const { data: result, error: fulfillError } = await admin.rpc(
    "fulfill_gateway_payment",
    {
      p_checkout_id: checkout.id,
      p_subscription_id: subscriptionId,
      p_invoice_id: invoiceId,
      p_variant_id: checkout.variant_id,
    },
  );
  if (fulfillError) return json({ error: "payment_not_fulfilled" }, 500);
  return json(result);
});

async function verifySignature(
  raw: string,
  signatureHex: string,
  secret: string,
): Promise<boolean> {
  if (!signatureHex) return false;
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sigBytes = await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(raw));
  const digestHex = Array.from(new Uint8Array(sigBytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return timingSafeEqualHex(digestHex, signatureHex.trim());
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function cors(res: Response): Response {
  res.headers.set("Access-Control-Allow-Origin", "*");
  res.headers.set(
    "Access-Control-Allow-Headers",
    "authorization, x-client-info, apikey, content-type, x-signature",
  );
  res.headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  return res;
}

function json(body: unknown, status = 200): Response {
  return cors(
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    }),
  );
}
