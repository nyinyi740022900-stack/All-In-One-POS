// Edge Function: activate a license key and bind it to the calling device,
// plus self-service multi-device actions for an already-activated shop.
//
// Actions (POST body { action, ... }, action defaults to "activate" for
// backward compatibility with existing clients that never sent one):
//   activate (default) { key, device_id }     -> bind a key to this device
//   request_device_slot {}                    -> claim a key for a NEW device
//                                                 under the caller's own shop
//   release_device { device_id }              -> free up a device slot so it
//                                                 can be reused by a new device
//   create_shop_login { email, password }     -> caller (already activated,
//                                                 i.e. has shop_id) creates a
//                                                 real login for their shop,
//                                                 additive to device-key
//                                                 activation, role: 'owner'
//   invite_staff { email, password }          -> owner-role caller creates a
//                                                 real staff login under
//                                                 their own shop_id
//   revoke_staff { user_id }                  -> owner-role caller bans a
//                                                 staff account it created
//   list_staff {}                             -> owner-role caller lists
//                                                 staff accounts under their
//                                                 own shop_id (auth.users
//                                                 isn't client-queryable)
//
// activate flow:
//  1. Authenticate the caller (anonymous or otherwise) from the JWT.
//  2. Look up the license by key using the service role (bypasses RLS).
//  3. Validate: exists, device not bound to a different device, not past grace.
//  4. Bind the device, stamp last_verified_at.
//  5. Set the caller's app_metadata.shop_id so RLS scopes them to this shop.
//  6. Return license details; the client refreshes its session to pick up the
//     new claim.
//
// Deploy: supabase functions deploy activate

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GRACE_DAYS = 7;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  // Identify the caller from their JWT.
  const asUser = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ ok: false, error: "not_authenticated" }, 401);
  }
  const userId = userData.user.id;

  let body: {
    action?: string;
    key?: string;
    device_id?: string;
    email?: string;
    password?: string;
    user_id?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "bad_request" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);
  const action = body.action ?? "activate";

  if (action === "request_device_slot") {
    return handleRequestDeviceSlot(admin, userData.user);
  }
  if (action === "release_device") {
    return handleReleaseDevice(admin, userData.user, body.device_id ?? "");
  }
  if (action === "create_shop_login") {
    return handleCreateShopLogin(
      admin,
      userData.user,
      body.email ?? "",
      body.password ?? "",
    );
  }
  if (action === "invite_staff") {
    return handleInviteStaff(
      admin,
      userData.user,
      body.email ?? "",
      body.password ?? "",
    );
  }
  if (action === "revoke_staff") {
    return handleRevokeStaff(admin, userData.user, body.user_id ?? "");
  }
  if (action === "list_staff") {
    return handleListStaff(admin, userData.user);
  }

  const key = (body.key ?? "").trim();
  const deviceId = (body.device_id ?? "").trim();
  if (!key || !deviceId) {
    return json({ ok: false, error: "bad_request" }, 400);
  }

  // Rate limit: the `activate` action accepts an arbitrary key string and
  // reports back whether it was valid — exactly the surface a brute-force
  // script would target. At most 10 attempts per IP per 15 minutes; counted
  // before the lookup so rapid guesses can't dodge the limit.
  const ip = (req.headers.get("x-forwarded-for") ?? "unknown")
    .split(",")[0]
    .trim();
  const windowStart = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const { count } = await admin
    .from("activate_attempts")
    .select("id", { count: "exact", head: true })
    .eq("ip", ip)
    .gte("created_at", windowStart);
  if ((count ?? 0) >= 10) {
    // 200, not 429 — every other soft/business-logic error this action
    // returns (invalid_key, device_mismatch) uses 200 so the client's
    // `res.data` parsing path (not its exception path) handles it.
    return json({ ok: false, error: "rate_limited" }, 200);
  }
  await admin.from("activate_attempts").insert({ ip });

  const { data: license, error: licErr } = await admin
    .from("licenses")
    .select("*")
    .eq("key", key)
    .maybeSingle();

  if (licErr) return json({ ok: false, error: "server_error" }, 500);
  if (!license) return json({ ok: false, error: "invalid_key" }, 200);

  // Device binding: first activation claims the device; later activations must
  // match (prevents one key being shared across many devices).
  if (license.device_id && license.device_id !== deviceId) {
    return json({ ok: false, error: "device_mismatch" }, 200);
  }

  const now = new Date();
  const expiresAt = new Date(license.expires_at);
  const graceEnd = new Date(expiresAt.getTime() + GRACE_DAYS * 86400000);
  const status = now <= expiresAt
    ? "active"
    : now <= graceEnd
    ? "grace"
    : "expired";

  const { error: updErr } = await admin
    .from("licenses")
    .update({
      device_id: deviceId,
      last_verified_at: now.toISOString(),
      activated_at: license.activated_at ?? now.toISOString(),
      status,
      updated_at: now.toISOString(),
    })
    .eq("id", license.id);
  if (updErr) return json({ ok: false, error: "server_error" }, 500);

  // Scope the caller to this shop via app_metadata (lands in future JWTs).
  const { error: metaErr } = await admin.auth.admin.updateUserById(userId, {
    app_metadata: { shop_id: license.shop_id },
  });
  if (metaErr) return json({ ok: false, error: "server_error" }, 500);

  return json({
    ok: true,
    shop_id: license.shop_id,
    plan: license.plan,
    status,
    expires_at: license.expires_at,
    realtime_enabled: license.realtime_enabled === true,
    activated_at: license.activated_at ?? now.toISOString(),
  }, 200);
});

// deno-lint-ignore no-explicit-any
type SupabaseUser = any;
// deno-lint-ignore no-explicit-any
type AdminClient = any;

function shopIdOf(user: SupabaseUser): string | null {
  const meta = user.app_metadata as Record<string, unknown> | null;
  const shopId = meta?.shop_id;
  return typeof shopId === "string" && shopId.length > 0 ? shopId : null;
}

function roleOf(user: SupabaseUser): string | null {
  const meta = user.app_metadata as Record<string, unknown> | null;
  const role = meta?.role;
  return typeof role === "string" && role.length > 0 ? role : null;
}

// Real login, additive to device-key activation (see the module doc comment
// for the three actions below). None of this touches RLS or any existing
// table — it only stamps app_metadata on auth.users, same trust boundary
// `activate` itself already stamps shop_id onto.

// The caller must already carry a shop_id claim (i.e. this device/session is
// already activated the normal way) — that's what proves they own this shop
// well enough to attach a real login to it. Creates a NEW real auth user
// (not the caller's own anonymous one) with role: 'owner', so the shop can
// keep using its existing anonymous/device sessions unaffected while also
// gaining a real email+password login.
async function handleCreateShopLogin(
  admin: AdminClient,
  user: SupabaseUser,
  email: string,
  password: string,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  if (!email || !password) return json({ ok: false, error: "bad_request" }, 400);

  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: { shop_id: shopId, role: "owner" },
  });
  if (error) {
    // Supabase returns a generic error for "email already registered" —
    // surface it as a distinct code the client can show a clear message for.
    const msg = String(error.message ?? "").toLowerCase();
    if (msg.includes("already") || msg.includes("registered")) {
      return json({ ok: false, error: "email_taken" }, 200);
    }
    return json({ ok: false, error: "server_error" }, 500);
  }
  return json({ ok: true, user_id: data.user?.id, email }, 200);
}

// Owner-role only (mirrors the `admin` Edge Function's role check). Creates
// a staff login under the OWNER's OWN shop_id — never a shop_id the caller
// passes in, so a staff account can never be minted for someone else's shop.
async function handleInviteStaff(
  admin: AdminClient,
  user: SupabaseUser,
  email: string,
  password: string,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  if (roleOf(user) !== "owner") {
    return json({ ok: false, error: "forbidden" }, 403);
  }
  if (!email || !password) return json({ ok: false, error: "bad_request" }, 400);

  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: { shop_id: shopId, role: "staff" },
  });
  if (error) {
    const msg = String(error.message ?? "").toLowerCase();
    if (msg.includes("already") || msg.includes("registered")) {
      return json({ ok: false, error: "email_taken" }, 200);
    }
    return json({ ok: false, error: "server_error" }, 500);
  }
  return json({ ok: true, user_id: data.user?.id, email }, 200);
}

// Owner-role only. Bans the target account indefinitely (Supabase's
// documented idiom for a permanent ban — there's no separate "delete" that
// keeps referential history clean, and banning is reversible if the owner
// re-invites/un-bans later). Scoped to the CALLER's own shop_id so an owner
// can never revoke another shop's staff account.
async function handleRevokeStaff(
  admin: AdminClient,
  user: SupabaseUser,
  targetUserId: string,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  if (roleOf(user) !== "owner") {
    return json({ ok: false, error: "forbidden" }, 403);
  }
  if (!targetUserId) return json({ ok: false, error: "bad_request" }, 400);

  const { data: targetData, error: getErr } = await admin.auth.admin
    .getUserById(targetUserId);
  if (getErr || !targetData?.user) {
    return json({ ok: false, error: "not_found" }, 200);
  }
  if (shopIdOf(targetData.user) !== shopId) {
    return json({ ok: false, error: "forbidden" }, 403);
  }

  const { error } = await admin.auth.admin.updateUserById(targetUserId, {
    ban_duration: "876000h", // ~100 years — Supabase's "indefinite ban" idiom
  });
  if (error) return json({ ok: false, error: "server_error" }, 500);
  return json({ ok: true }, 200);
}

// Owner-role only. Lists staff accounts under the caller's own shop_id —
// auth.users has no RLS a client could query directly, so this is the only
// way the app can show "who's been invited." Filters client-side after a
// single admin listUsers page; fine at this app's per-shop staff-count scale
// (a handful of people), not built to paginate thousands of users.
async function handleListStaff(
  admin: AdminClient,
  user: SupabaseUser,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  if (roleOf(user) !== "owner") {
    return json({ ok: false, error: "forbidden" }, 403);
  }

  const { data, error } = await admin.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  if (error) return json({ ok: false, error: "server_error" }, 500);

  // deno-lint-ignore no-explicit-any
  const staff = (data.users as any[])
    .filter((u) => shopIdOf(u) === shopId && roleOf(u) === "staff")
    .map((u) => ({
      user_id: u.id,
      email: u.email,
      banned: (u.banned_until ?? null) !== null &&
        new Date(u.banned_until) > new Date(),
    }));
  return json({ ok: true, staff }, 200);
}

// Claims a device slot for the caller's own shop: reuses a released
// (device_id null) key if one exists, mints a new one if the shop is under
// its free-device limit, or reports that a device fee is owed. The actual
// binding to a physical device still happens through the normal `activate`
// action once the owner types (or scans) the returned key on the new phone.
async function handleRequestDeviceSlot(
  admin: AdminClient,
  user: SupabaseUser,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);

  const { data: key, error } = await admin.rpc("claim_device_slot", {
    p_shop_id: shopId,
  });
  if (error) return json({ ok: false, error: "server_error" }, 500);

  if (key) {
    return json({ ok: true, key }, 200);
  }

  const { data: feeRow } = await admin
    .from("app_config")
    .select("value")
    .eq("key", "device.extra_fee")
    .maybeSingle();
  const fee = Number(feeRow?.value ?? "0") || 0;
  return json({ ok: false, error: "payment_required", fee }, 200);
}

// Self-service: releases one of the CALLER'S OWN shop's devices so its key
// can be reused for a new device. Scoped by shop_id so a shop can never
// release a device belonging to another shop.
async function handleReleaseDevice(
  admin: AdminClient,
  user: SupabaseUser,
  deviceId: string,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  if (!deviceId) return json({ ok: false, error: "bad_request" }, 400);

  const { data, error } = await admin
    .from("licenses")
    .update({ device_id: null, updated_at: new Date().toISOString() })
    .eq("device_id", deviceId)
    .eq("shop_id", shopId)
    .select("key");
  if (error) return json({ ok: false, error: "server_error" }, 500);
  if (!data || data.length === 0) {
    return json({ ok: false, error: "not_found" }, 200);
  }
  return json({ ok: true }, 200);
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
