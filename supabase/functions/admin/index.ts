// Edge Function: admin console backend.
//
// One authenticated endpoint for the vendor admin dashboard. Verifies the
// caller is an admin (JWT app_metadata.role === 'admin'), then performs the
// requested action with the service role. Keeps the service key server-side —
// the web dashboard only ever holds the anon key + an admin session.
//
// Actions (POST body { action, ... }):
//   list_licenses                         -> licenses (newest first)
//   create_license { shop_id, plan, months } -> { key }
//
// Deploy: supabase functions deploy admin

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { signOfflineToken } from "../_shared/offline_token.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return cors(new Response(null, { status: 204 }));
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  // Identify + authorize the caller.
  const asUser = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ error: "not_authenticated" }, 401);
  }
  const role = (userData.user.app_metadata as Record<string, unknown> | null)
    ?.role;
  if (role !== "admin") return json({ error: "forbidden" }, 403);

  let body: {
    action?: string;
    shop_id?: string;
    shop_name?: string;
    plan?: string;
    months?: number;
    key?: string;
    device_id?: string;
    request_id?: string;
    reason?: string;
    config?: Record<string, string>;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);

  switch (body.action) {
    case "list_licenses": {
      const { data, error } = await admin
        .from("licenses")
        .select("*")
        .order("updated_at", { ascending: false })
        .limit(500);
      if (error) return json({ error: "server_error" }, 500);
      return json({ rows: data });
    }

    case "extend_by_device": {
      // Extend whatever license is bound to this App Reference ID / device.
      const dev = (body.device_id ?? "").trim();
      const months = body.months ?? 1;
      if (!dev) return json({ error: "bad_request" }, 400);
      const { data: lic, error: findErr } = await admin
        .from("licenses")
        .select("key, shop_name")
        .eq("device_id", dev)
        .maybeSingle();
      if (findErr) return json({ error: "server_error" }, 500);
      if (!lic) return json({ error: "not_found" }, 404);
      const { data, error } = await admin.rpc("renew_license", {
        p_key: lic.key,
        p_months: months,
      });
      if (error) return json({ error: "server_error", detail: error.message }, 500);
      await logEvent(admin, {
        device_id: dev,
        shop_name: lic.shop_name,
        key: lic.key,
        action: "extend",
        months,
        expires_at: data,
      });
      return json({ expires_at: data, key: lic.key });
    }

    case "sign_offline": {
      // Mint an offline signed license token the admin can send to a shop with
      // no connectivity. Signed with the Ed25519 private key held as a secret.
      // See _shared/offline_token.ts — activate's automatic issuance uses the
      // exact same signing logic, just triggered on every activation instead
      // of only when an admin hand-fulfills a request.
      try {
        const { token, expiresAt } = await signOfflineToken({
          shopId: body.shop_id ?? "",
          shopName: body.shop_name,
          plan: body.plan,
          months: body.months,
          deviceId: body.device_id,
        });
        return json({ token, expires_at: expiresAt });
      } catch (e) {
        const msg = e instanceof Error ? e.message : "server_error";
        if (msg === "signing_key_missing" || msg === "bad_request") {
          return json({ error: msg }, msg === "bad_request" ? 400 : 500);
        }
        return json({ error: "server_error" }, 500);
      }
    }

    case "reset_device": {
      // Clear the device binding so a reinstalled user can re-activate.
      const dev = (body.device_id ?? "").trim();
      if (!dev) return json({ error: "bad_request" }, 400);
      const { data, error } = await admin
        .from("licenses")
        .update({ device_id: null, updated_at: new Date().toISOString() })
        .eq("device_id", dev)
        .select("key");
      if (error) return json({ error: "server_error" }, 500);
      return json({ ok: true, cleared: (data ?? []).length });
    }

    case "list_requests": {
      const { data, error } = await admin
        .from("license_requests")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(500);
      if (error) return json({ error: "server_error" }, 500);
      return json({ rows: data });
    }

    case "fulfill_request": {
      const reqId = (body.request_id ?? "").trim();
      if (!reqId) return json({ error: "bad_request" }, 400);
      const { data: reqRow, error: reqErr } = await admin
        .from("license_requests")
        .select("*")
        .eq("id", reqId)
        .maybeSingle();
      if (reqErr) return json({ error: "server_error" }, 500);
      if (!reqRow) return json({ error: "not_found" }, 404);

      const months = body.months ?? reqRow.months ?? 1;
      const dev = (reqRow.device_id ?? "").trim();
      const reqShopId = (reqRow.shop_id ?? "").trim();

      // If this shop already has a license, this is a RENEWAL → extend it.
      // Prefer shop_id (the app sends its own shopId whenever it already has
      // one) over device_id: a shop can have multiple devices/rows
      // (0025_multi_device_licensing.sql) with only one device_id stamped on
      // any given row, so a device_id-only lookup can miss and wrongly fall
      // through to "issue new" for a shop that's already paying. shop_id
      // matches ANY of the shop's rows — good enough, since renew_license
      // already extends every row sharing that shop_id. device_id stays as
      // the fallback for requests submitted before this column existed, or a
      // genuinely brand-new offline customer with no shop_id yet.
      let existing: { key: string; shop_id: string } | null = null;
      if (reqShopId) {
        const { data } = await admin
          .from("licenses")
          .select("key, shop_id")
          .eq("shop_id", reqShopId)
          .eq("is_deleted", false)
          .order("created_at", { ascending: true })
          .limit(1)
          .maybeSingle();
        existing = data;
      } else if (dev) {
        const { data } = await admin
          .from("licenses")
          .select("key, shop_id")
          .eq("device_id", dev)
          .maybeSingle();
        existing = data;
      }

      let key: string;
      let referredShopId: string;
      let expiresAt: string | null = null;
      let action: string;
      if (existing?.key) {
        const { data, error } = await admin.rpc("renew_license", {
          p_key: existing.key,
          p_months: months,
        });
        if (error) return json({ error: "server_error", detail: error.message }, 500);
        key = existing.key;
        referredShopId = existing.shop_id as string;
        expiresAt = data as string;
        action = "extend";
      } else {
        const shopId = `shop-${reqId.replace(/-/g, "").slice(0, 10)}`;
        const { data: newKey, error: mkErr } = await admin.rpc("create_license", {
          p_shop_id: shopId,
          p_plan: reqRow.plan ?? "monthly",
          p_months: months,
          p_shop_name: reqRow.shop_name ?? null,
        });
        if (mkErr) return json({ error: "server_error", detail: mkErr.message }, 500);
        key = newKey as string;
        referredShopId = shopId;
        action = "issue";
      }

      await admin
        .from("license_requests")
        .update({
          status: "fulfilled",
          issued_key: key,
          updated_at: new Date().toISOString(),
        })
        .eq("id", reqId);
      await logEvent(admin, {
        device_id: dev || null,
        shop_name: reqRow.shop_name ?? null,
        key,
        action,
        months,
        expires_at: expiresAt,
      });

      // Referral: link on first attribution, then accrue a commission for the
      // referrer on THIS real payment (never on recruitment alone).
      await ensureReferralLink(admin, {
        referredShopId,
        code: (reqRow.referred_by_code ?? "").trim(),
      });
      await accrueReferralCommission(admin, {
        referredShopId,
        licenseKey: key,
        baseAmount: reqRow.amount ?? 0,
        sourceRequestId: reqId,
      });
      return json({ key, action });
    }

    case "reject_request": {
      const reqId = (body.request_id ?? "").trim();
      if (!reqId) return json({ error: "bad_request" }, 400);
      const reason = (body.reason ?? "").trim();
      const { data: reqRow, error: reqErr } = await admin
        .from("license_requests")
        .select("*")
        .eq("id", reqId)
        .maybeSingle();
      if (reqErr) return json({ error: "server_error" }, 500);
      if (!reqRow) return json({ error: "not_found" }, 404);

      await admin
        .from("license_requests")
        .update({
          status: "rejected",
          reject_reason: reason || null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", reqId);
      await logEvent(admin, {
        device_id: (reqRow.device_id ?? "").trim() || null,
        shop_name: reqRow.shop_name ?? null,
        action: "reject",
      });
      return json({ ok: true });
    }

    case "list_referrals": {
      const { data, error } = await admin
        .from("referrals")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(500);
      if (error) return json({ error: "server_error" }, 500);
      return json({ rows: data });
    }

    case "list_commissions": {
      const { data, error } = await admin
        .from("referral_commissions")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(500);
      if (error) return json({ error: "server_error" }, 500);
      return json({ rows: data });
    }

    case "apply_referral_credit": {
      // Admin redeems a referrer's balance into whole months on their own
      // license. Delegates to the locked SQL function so it can't race with a
      // self-service redeem (double-spend). Remainder stays as balance.
      const sid = (body.shop_id ?? "").trim();
      if (!sid) return json({ error: "bad_request" }, 400);
      const { data, error } = await admin.rpc("apply_referral_credit_for", {
        p_shop_id: sid,
      });
      if (error) {
        const detail = error.message ?? "";
        if (detail.includes("no license")) return json({ error: "not_found" }, 404);
        return json({ error: "server_error", detail }, 500);
      }
      return json(data);
    }

    case "list_events": {
      const { data, error } = await admin
        .from("license_events")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(500);
      if (error) return json({ error: "server_error" }, 500);
      return json({ rows: data });
    }

    case "get_config": {
      const { data, error } = await admin.from("app_config").select("key, value");
      if (error) return json({ error: "server_error" }, 500);
      return json({ rows: data });
    }

    case "set_config": {
      const entries = Object.entries(body.config ?? {});
      if (entries.length === 0) return json({ error: "bad_request" }, 400);
      const rows = entries.map(([key, value]) => ({
        key,
        value: `${value}`,
        updated_at: new Date().toISOString(),
      }));
      const { error } = await admin.from("app_config").upsert(rows);
      if (error) return json({ error: "server_error", detail: error.message }, 500);
      return json({ ok: true });
    }

    case "list_carriers": {
      const { data, error } = await admin
        .from("delivery_carriers")
        .select("id, carrier, account_id, base_url, enabled, api_key, updated_at")
        .order("carrier");
      if (error) return json({ error: "server_error" }, 500);
      // Never hand the raw API key back to the browser — expose only whether
      // one is set + its last 4 chars so the admin can recognise it.
      // deno-lint-ignore no-explicit-any
      const rows = (data ?? []).map((r: any) => ({
        id: r.id,
        carrier: r.carrier,
        account_id: r.account_id,
        base_url: r.base_url,
        enabled: r.enabled,
        updated_at: r.updated_at,
        api_key_set: !!(r.api_key && `${r.api_key}`.length > 0),
        api_key_last4: r.api_key ? `${r.api_key}`.slice(-4) : null,
      }));
      return json({ rows });
    }

    case "set_carrier": {
      const c = body.carrier ?? {};
      const name = (c.carrier ?? "").trim();
      if (!name) return json({ error: "bad_request" }, 400);
      // deno-lint-ignore no-explicit-any
      const row: Record<string, any> = {
        carrier: name,
        account_id: (c.account_id ?? "").trim() || null,
        base_url: (c.base_url ?? "").trim() || null,
        enabled: c.enabled === true,
        updated_at: new Date().toISOString(),
      };
      if (c.id) row.id = c.id;
      // Only overwrite the stored secret when a new non-empty key is supplied,
      // so editing other fields never wipes it.
      if (typeof c.api_key === "string" && c.api_key.trim().length > 0) {
        row.api_key = c.api_key.trim();
      }
      const { error } = await admin.from("delivery_carriers").upsert(row);
      if (error) return json({ error: "server_error", detail: error.message }, 500);
      return json({ ok: true });
    }

    case "delete_carrier": {
      const id = (body.id ?? "").trim();
      if (!id) return json({ error: "bad_request" }, 400);
      const { error } = await admin.from("delivery_carriers").delete().eq("id", id);
      if (error) return json({ error: "server_error" }, 500);
      return json({ ok: true });
    }

    case "create_license": {
      const shopId = (body.shop_id ?? "").trim();
      const plan = (body.plan ?? "monthly").trim();
      const months = body.months ?? 1;
      if (!shopId) return json({ error: "bad_request" }, 400);
      const { data, error } = await admin.rpc("create_license", {
        p_shop_id: shopId,
        p_plan: plan,
        p_months: months,
        p_shop_name: (body.shop_name ?? "").trim() || null,
      });
      if (error) return json({ error: "server_error", detail: error.message }, 500);
      return json({ key: data });
    }

    default:
      return json({ error: "unknown_action" }, 400);
  }
});

// deno-lint-ignore no-explicit-any
async function logEvent(admin: any, event: Record<string, unknown>) {
  try {
    await admin.from("license_events").insert(event);
  } catch (_) {
    // audit log is best-effort; never fail the main action over it
  }
}

// Read a handful of app_config keys into a { key: value } map.
// deno-lint-ignore no-explicit-any
async function getConfig(admin: any, keys: string[]): Promise<Record<string, string>> {
  const { data } = await admin.from("app_config").select("key, value").in(
    "key",
    keys,
  );
  const out: Record<string, string> = {};
  for (const row of (data ?? []) as Array<{ key: string; value: string }>) {
    out[row.key] = row.value;
  }
  return out;
}

// Attribute a referred shop to its referrer, exactly once. No-op if the code is
// blank, the shop is already linked, the code is unknown, or it's a self-refer.
// deno-lint-ignore no-explicit-any
async function ensureReferralLink(
  admin: any,
  { referredShopId, code }: { referredShopId: string; code: string },
) {
  try {
    if (!referredShopId || !code) return;
    const { data: already } = await admin
      .from("referrals")
      .select("id")
      .eq("referred_shop_id", referredShopId)
      .maybeSingle();
    if (already) return; // never re-attribute on a later renewal
    const { data: referrer } = await admin
      .from("licenses")
      .select("shop_id")
      .eq("referral_code", code)
      .maybeSingle();
    if (!referrer?.shop_id) return; // unknown code
    if (referrer.shop_id === referredShopId) return; // no self-refer
    await admin.from("referrals").insert({
      referrer_shop_id: referrer.shop_id,
      referred_shop_id: referredShopId,
      referral_code: code,
    });
  } catch (_) {
    // referral wiring is best-effort; never fail the main payment action
  }
}

// Accrue one commission for a referred shop's real payment. Idempotent per
// source_request_id (unique), so re-fulfilling can't double-pay.
// deno-lint-ignore no-explicit-any
async function accrueReferralCommission(
  admin: any,
  {
    referredShopId,
    licenseKey,
    baseAmount,
    sourceRequestId,
  }: {
    referredShopId: string;
    licenseKey: string;
    baseAmount: number;
    sourceRequestId: string;
  },
) {
  try {
    if (!referredShopId || !(baseAmount > 0)) return;
    const cfg = await getConfig(admin, ["referral.enabled", "referral.rate"]);
    // Enabled unless explicitly turned off (tolerate casing / common values).
    const enabled = (cfg["referral.enabled"] ?? "true").trim().toLowerCase();
    if (["false", "0", "off", "no"].includes(enabled)) return;
    const rate = parseFloat(cfg["referral.rate"] ?? "0");
    if (!(rate > 0)) return;

    const { data: link } = await admin
      .from("referrals")
      .select("referrer_shop_id")
      .eq("referred_shop_id", referredShopId)
      .eq("is_active", true)
      .maybeSingle();
    if (!link?.referrer_shop_id) return; // not a referred shop

    const amount = Math.round(baseAmount * rate);
    if (amount <= 0) return;
    await admin
      .from("referral_commissions")
      .upsert({
        referrer_shop_id: link.referrer_shop_id,
        referred_shop_id: referredShopId,
        license_key: licenseKey,
        base_amount: baseAmount,
        rate,
        amount,
        source_request_id: sourceRequestId,
      }, { onConflict: "source_request_id", ignoreDuplicates: true });
  } catch (_) {
    // best-effort; never fail the main payment action
  }
}

function cors(res: Response): Response {
  res.headers.set("Access-Control-Allow-Origin", "*");
  res.headers.set(
    "Access-Control-Allow-Headers",
    "authorization, x-client-info, apikey, content-type",
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
