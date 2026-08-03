// Edge Function: grant (or return) a device's one free trial.
//
// Server-side so the trial can't be farmed by reinstalling: the trial license
// is keyed to the device id. Also stamps app_metadata.shop_id so the trial
// user's data syncs under shop-isolation RLS (same as `activate`).
//
// Deploy: supabase functions deploy start_trial

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TRIAL_MONTHS = 2;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  const asUser = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ ok: false, error: "not_authenticated" }, 401);
  }
  const userId = userData.user.id;

  let body: { device_id?: string; shop_name?: string };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "bad_request" }, 400);
  }
  const deviceId = (body.device_id ?? "").trim();
  if (!deviceId) return json({ ok: false, error: "bad_request" }, 400);

  const admin = createClient(supabaseUrl, serviceKey);
  const shopId = `shop-${deviceId.replace(/-/g, "").slice(0, 10)}`;

  // One trial per device: reuse an existing one instead of resetting it.
  const { data: existing } = await admin
    .from("licenses")
    .select("*")
    .eq("device_id", deviceId)
    .eq("plan", "trial")
    .maybeSingle();

  let license = existing;
  if (!license) {
    const key = "TRIAL-" +
      crypto.randomUUID().replace(/-/g, "").slice(0, 12).toUpperCase();
    const now = new Date();
    const expires = new Date(now);
    expires.setMonth(expires.getMonth() + TRIAL_MONTHS);
    // Give trial shops a shareable referral code too (this insert bypasses the
    // create_license RPC, which is where paid licenses get theirs).
    const { data: refCode } = await admin.rpc("gen_referral_code");
    const { data: created, error: insErr } = await admin
      .from("licenses")
      .insert({
        shop_id: shopId,
        shop_name: body.shop_name ?? null,
        key,
        plan: "trial",
        status: "active",
        device_id: deviceId,
        expires_at: expires.toISOString(),
        activated_at: now.toISOString(),
        referral_code: refCode,
        tier: "offline",
      })
      .select("*")
      .single();
    if (insErr) return json({ ok: false, error: "server_error", detail: insErr.message }, 500);
    license = created;
  }

  // Scope the caller to this shop so their data syncs under RLS.
  await admin.auth.admin.updateUserById(userId, {
    app_metadata: { shop_id: license.shop_id },
  });

  return json({
    ok: true,
    key: license.key,
    shop_id: license.shop_id,
    plan: "trial",
    expires_at: license.expires_at,
    activated_at: license.activated_at,
    tier: license.tier ?? "offline",
  });
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
