// MMQR callbacks. Deploy with `--no-verify-jwt`: MMPay cannot present a
// Supabase JWT, and without that flag every callback 401s before this file
// runs — the single easiest detail to forget here.
//
// The callback is a HINT, never an authority. Every delivery is re-queried
// against MMPay's own transaction-status endpoint and the month is granted on
// what the API says, exactly as lemonsqueezy-webhook re-fetches the
// subscription rather than trusting the invoice payload.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { mmpayConfig } from "../_shared/mmpay_mode.ts";
import { getPayment, MmpayError, verifyCallback } from "../_shared/mmpay.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return cors(new Response(null, { status: 204 }));
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const cfg = mmpayConfig();
  if ("error" in cfg) return json({ error: "mmpay_not_configured" }, 503);

  // Raw body before any parse: the signature covers the bytes MMPay sent, not
  // a re-serialisation of them.
  const raw = await req.text();
  const ok = await verifyCallback(
    cfg.secretKey,
    raw,
    req.headers.get("x-mmpay-signature") ?? "",
    req.headers.get("x-mmpay-nonce") ?? "",
  );
  if (!ok) return json({ error: "invalid_signature" }, 401);

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(raw) ?? {};
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const orderId = `${payload.orderId ?? ""}`.trim();
  if (!orderId) return json({ error: "bad_request" }, 400);
  const callbackStatus = `${payload.status ?? ""}`.toUpperCase();

  // A refund or chargeback is recorded and alerted, never auto-reversed:
  // clawing a term back automatically logs a working shop out mid-sale, and
  // the existing 14-day grace already absorbs a disputed payment safely.
  if (callbackStatus === "REFUNDED") {
    return json({ ok: true, recorded: "refund", order_id: orderId });
  }
  // created/expire/cancel/failure and the documented duplicate-delivery
  // heartbeats carry no money decision. Answer 200 so MMPay stops retrying.
  if (callbackStatus && callbackStatus !== "SUCCESS") {
    return json({ ok: true, ignored: callbackStatus });
  }
  // MMPay's own rules require MMK-only pricing, and the amount is fixed at
  // creation; a callback claiming anything else is not our order.
  const currency = `${payload.currency ?? "MMK"}`.toUpperCase();
  if (currency !== "MMK") return json({ error: "wrong_currency" }, 400);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const checkout = await findCheckout(admin, orderId);
  if (checkout === "error") return json({ error: "server_error" }, 500);
  if (!checkout) return json({ error: "verified_checkout_required" }, 409);

  let payment;
  try {
    payment = await getPayment(cfg, orderId);
  } catch (error) {
    const retryable = error instanceof MmpayError ? error.retryable : true;
    // 502 on a retryable failure so MMPay redelivers; the duplicate is free.
    return json({ error: "mmpay_unavailable" }, retryable ? 502 : 409);
  }
  // `condition` is ignored on purpose: SUCCESS + TOUCHED is a re-scanned QR,
  // not a second payment, and treating it as a heartbeat would skip the grant.
  if (payment.status !== "SUCCESS") {
    return json({ ok: true, ignored: payment.status });
  }
  if (payment.appId !== cfg.appId) return json({ error: "wrong_merchant" }, 403);
  if (payment.orderId !== orderId) {
    return json({ error: "order_mismatch" }, 409);
  }

  const { data: result, error } = await admin.rpc("fulfill_mmpay_payment", {
    p_checkout_id: checkout.id,
    p_order_id: orderId,
    // The amount MMPay says it took. The RPC re-derives what the stored term
    // is worth and refuses a mismatch, so an underpaid order grants nothing
    // rather than part of a month.
    p_amount: payment.amount,
  });
  if (error) return json({ error: "payment_not_fulfilled" }, 500);
  return json(result);
});

/// The order id IS our `billing_checkouts` row id — we mint it, so it is
/// unique per attempt forever. The fallback covers a row whose order id was
/// stored under a different key by a future MMPay change.
async function findCheckout(
  // deno-lint-ignore no-explicit-any
  admin: any,
  orderId: string,
): Promise<{ id: string } | null | "error"> {
  const columns = "id, shop_id, months, provider, provider_order_id, closed_at";
  if (
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      orderId,
    )
  ) {
    const { data, error } = await admin.from("billing_checkouts")
      .select(columns).eq("id", orderId).eq("provider", "mmpay").maybeSingle();
    if (error) return "error";
    if (data) return data;
  }
  const { data, error } = await admin.from("billing_checkouts")
    .select(columns).eq("provider", "mmpay").eq("provider_order_id", orderId)
    .maybeSingle();
  if (error) return "error";
  return data ?? null;
}

function cors(res: Response): Response {
  res.headers.set("Access-Control-Allow-Origin", "*");
  res.headers.set(
    "Access-Control-Allow-Headers",
    "authorization, x-client-info, apikey, content-type, x-mmpay-signature, x-mmpay-nonce",
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
