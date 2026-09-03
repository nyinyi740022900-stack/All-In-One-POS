// Edge Function: Lemon Squeezy webhook — international (non-Myanmar) Premium
// subscriptions bought via the in-app checkout (see `_openLemonSqueezyCheckout`
// in `lib/features/license/license_screen.dart`). Extends/mints a license the
// exact same way the `admin` function's `fulfill_request` action does for a
// manually-approved Myanmar payment — same `create_license`/`renew_license`
// RPCs, same `license_events` audit log — so a Lemon Squeezy order is
// indistinguishable from an admin-approved one once it lands.
//
// No JWT: Lemon Squeezy calls this directly with no Authorization header, so
// it MUST be deployed with --no-verify-jwt. Authenticity comes entirely from
// the HMAC-SHA256 signature check below — do that before anything else.
//
// Myanmar's /renew web page, license_requests table, and the admin Requests
// tab are untouched by this function.
//
// Deploy: supabase functions deploy lemonsqueezy-webhook --no-verify-jwt --project-ref gnikispsurwrmkspuisj
// Secret: supabase secrets set LEMONSQUEEZY_WEBHOOK_SECRET=... --project-ref gnikispsurwrmkspuisj
// Register the deployed URL + this same secret as the webhook's signing
// secret in the Lemon Squeezy dashboard (Settings → Webhooks), subscribed to
// at least order_created and subscription_payment_success.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return cors(new Response(null, { status: 204 }));
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const secret = Deno.env.get("LEMONSQUEEZY_WEBHOOK_SECRET");
  if (!secret) return json({ error: "server_error" }, 500);

  // Verify over the RAW bytes before any JSON parsing.
  const raw = await req.text();
  const signatureHeader = req.headers.get("x-signature") ?? "";
  const valid = await verifySignature(raw, signatureHeader, secret);
  if (!valid) return json({ error: "invalid_signature" }, 401);

  // deno-lint-ignore no-explicit-any
  let payload: any;
  try {
    payload = JSON.parse(raw);
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const eventName: string = payload?.meta?.event_name ?? "";
  // Anything else (subscription_created, subscription_cancelled, order_refunded,
  // etc.) is ignored — 200 so Lemon Squeezy doesn't retry, no license change.
  if (eventName !== "order_created" && eventName !== "subscription_payment_success") {
    return json({ ok: true, ignored: eventName });
  }

  const customData = payload?.meta?.custom_data ?? {};
  const shopId: string = (customData.shop_id ?? "").trim();
  const deviceId: string = (customData.device_id ?? "").trim();
  if (!shopId) return json({ error: "bad_request", detail: "missing shop_id" }, 400);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceKey);

  // Idempotency FIRST — Lemon Squeezy retries on any non-2xx, and this must
  // never extend a license twice for the same event. Lemon Squeezy doesn't
  // send a dedicated event-id header, so the dedup key is event_name + the
  // resource id, which is stable across retries of the same delivery.
  const resourceId: string = payload?.data?.id ?? "";
  const eventId = `${eventName}:${resourceId}`;
  if (!resourceId) return json({ error: "bad_request", detail: "missing data.id" }, 400);

  const { error: insertErr } = await admin
    .from("lemonsqueezy_events")
    .insert({ id: eventId, event_name: eventName, shop_id: shopId, raw_payload: payload })
    .select("id")
    .single();
  if (insertErr) {
    // Unique-violation on `id` (23505) → a row for this exact event already
    // exists. That does NOT necessarily mean the license was ever actually
    // extended — this same insert runs BEFORE the mint below, so a delivery
    // that failed the mint (a transient DB error, say) after this row landed
    // would otherwise look "already handled" forever, since Lemon Squeezy's
    // retry is the only chance to finish it. `months` is only ever set AFTER
    // a successful renew_license/create_license call (see below), so treat
    // it as the real completion marker: only skip the mint when it's set.
    if (insertErr.code === "23505") {
      const { data: existingEvent } = await admin
        .from("lemonsqueezy_events")
        .select("months")
        .eq("id", eventId)
        .maybeSingle();
      if (existingEvent?.months != null) {
        return json({ ok: true, duplicate: true });
      }
      // else: this event landed but never finished minting — fall through
      // and retry the mint below instead of silently doing nothing.
    } else {
      return json({ error: "server_error", detail: insertErr.message }, 500);
    }
  }

  // Sibling-event guard — Lemon Squeezy fires BOTH `order_created` and
  // `subscription_payment_success` for the SAME purchase on every new
  // subscription (documented: "Initial order is placed: order_created,
  // subscription_created, subscription_payment_success"). The dedup above
  // is keyed by event_name:data.id, so it can't catch this — the two
  // events carry different resource ids for one purchase, and without this
  // guard a brand-new subscriber's first payment mints/extends TWICE
  // (confirmed live during #293's own end-to-end test, which exercised
  // exactly this sequence and mislabeled the second call a correct renewal).
  // A genuine renewal is always at least a full billing period (a month or
  // a year) later, so any OTHER already-completed event for this shop
  // within the last 10 minutes must be this same purchase's sibling
  // delivery, not a new one — skip the mint and mirror its months onto
  // this event's own row so a genuine retry of THIS exact delivery still
  // short-circuits via the check above.
  const siblingWindow = new Date(Date.now() - 10 * 60 * 1000).toISOString();
  const { data: siblingEvent } = await admin
    .from("lemonsqueezy_events")
    .select("months")
    .eq("shop_id", shopId)
    .neq("id", eventId)
    .not("months", "is", null)
    .gte("processed_at", siblingWindow)
    .order("processed_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (siblingEvent?.months != null) {
    await admin
      .from("lemonsqueezy_events")
      .update({ months: siblingEvent.months })
      .eq("id", eventId);
    return json({ ok: true, duplicate: true, reason: "sibling_event_recent" });
  }

  // Variant → months. `order_created`'s line item carries the variant
  // directly; a `subscription_payment_success` invoice does not repeat it,
  // so fall back to whatever months this shop's most recent resolved Lemon
  // Squeezy event used — set on the `order_created`/first payment above.
  // NOTE: field paths here are the well-documented, stable ones, but were
  // not checked against a captured live payload — confirm during the real
  // test-mode purchase (deploy plan §7 step 4) and adjust if a path is off.
  const attrs = payload?.data?.attributes ?? {};
  let variantId: string =
    `${attrs.variant_id ?? attrs.first_order_item?.variant_id ?? ""}`.trim();
  let months: number | null = null;
  if (variantId) {
    const { data: cfgRows } = await admin
      .from("app_config")
      .select("key, value")
      .in("key", [
        "pay.lemonsqueezy.variant_monthly",
        "pay.lemonsqueezy.variant_yearly",
      ]);
    const cfg: Record<string, string> = {};
    for (const r of cfgRows ?? []) cfg[r.key] = r.value ?? "";
    if (variantId === cfg["pay.lemonsqueezy.variant_yearly"]) months = 12;
    else if (variantId === cfg["pay.lemonsqueezy.variant_monthly"]) months = 1;
  }
  if (months == null) {
    const { data: prior } = await admin
      .from("lemonsqueezy_events")
      .select("months")
      .eq("shop_id", shopId)
      .not("months", "is", null)
      .order("processed_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    months = (prior?.months as number | undefined) ?? null;
  }
  // Fail closed, never guess: this event's own payload didn't carry a
  // resolvable variant AND this shop has no prior resolved event to fall
  // back on (its very first delivery, with an unmapped/unrecognized
  // variant) — silently defaulting to 1 month here would under-extend a
  // yearly purchase with no error and no way to notice. The event row
  // above stays with `months` null, a visible marker for manual follow-up,
  // rather than minting at a guessed duration.
  if (months == null) {
    return json(
      { error: "unresolvable_months", detail: "no variant match and no prior event for shop" },
      500,
    );
  }

  // Same shop_id-then-device_id lookup order `fulfill_request` uses.
  let existing: { key: string } | null = null;
  {
    const { data } = await admin
      .from("licenses")
      .select("key")
      .eq("shop_id", shopId)
      .eq("is_deleted", false)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();
    existing = data;
  }
  if (!existing?.key && deviceId) {
    const { data } = await admin
      .from("licenses")
      .select("key")
      .eq("device_id", deviceId)
      .maybeSingle();
    existing = data;
  }

  let key: string;
  let expiresAt: string | null = null;
  let action: string;
  if (existing?.key) {
    const { data, error } = await admin.rpc("renew_license", {
      p_key: existing.key,
      p_months: months,
    });
    if (error) return json({ error: "server_error", detail: error.message }, 500);
    key = existing.key;
    expiresAt = data as string;
    action = "extend";
  } else {
    const { data: newKey, error } = await admin.rpc("create_license", {
      p_shop_id: shopId,
      p_plan: months >= 12 ? "yearly" : "monthly",
      p_months: months,
      p_shop_name: null,
    });
    if (error) return json({ error: "server_error", detail: error.message }, 500);
    key = newKey as string;
    action = "issue";
  }

  await admin
    .from("lemonsqueezy_events")
    .update({ months })
    .eq("id", eventId);

  await logEvent(admin, {
    device_id: deviceId || null,
    key,
    action,
    months,
    expires_at: expiresAt,
  });

  return json({ ok: true, key, action });
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

// deno-lint-ignore no-explicit-any
async function logEvent(admin: any, event: Record<string, unknown>) {
  try {
    await admin.from("license_events").insert(event);
  } catch (_) {
    // audit log is best-effort; never fail the main action over it
  }
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
