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
//   create_branch { shop_name }                -> owner-role caller mints a
//                                                 BRAND NEW shop_id + trial
//                                                 license (no device bound
//                                                 yet) and auto-links it as
//                                                 a branch they own — the
//                                                 primary way to add a
//                                                 branch when already signed
//                                                 in with a real account, no
//                                                 separate key needed
//   link_branch { key, label }                -> owner-role caller registers
//                                                 another EXISTING shop_id
//                                                 (proven by its key) as a
//                                                 branch they own; upsert,
//                                                 so it also renames —
//                                                 secondary/advanced path
//                                                 for a shop that already
//                                                 exists separately. Shares
//                                                 the default action's per-IP
//                                                 rate limit, since it's the
//                                                 same "guess an arbitrary
//                                                 key string" brute-force
//                                                 surface.
//   list_branches {}                          -> owner-role caller lists
//                                                 every branch they've
//                                                 linked (incl. their own
//                                                 current shop_id)
//   unlink_branch { shop_id }                 -> owner-role caller removes a
//                                                 branch link
//   switch_branch { shop_id }                 -> owner-role caller re-scopes
//                                                 their OWN session to a
//                                                 branch they've linked; the
//                                                 client wipes+resyncs local
//                                                 data after this succeeds
//   signup_shop { shop_name, email, password,
//                 device_id }                  -> mints a BRAND NEW shop_id +
//                                                 2-month trial license +
//                                                 real owner login, all in
//                                                 one call — the only action
//                                                 that doesn't require a
//                                                 shop to already exist; the
//                                                 client signs in with the
//                                                 new credentials itself
//   set_tier { tier }                          -> owner-role caller
//                                                 self-service switches
//                                                 their OWN shop's pricing
//                                                 tier ('offline'/'online');
//                                                 affects the *suggested*
//                                                 renewal price only, never
//                                                 shop_id/session/data
//   delete_account { password }               -> owner-role caller permanently
//                                                 deletes their Auth users
//                                                 (owner+staff) for owned
//                                                 shops, licenses, and
//                                                 best-effort shop-scoped
//                                                 cloud rows — App Store /
//                                                 Play account-deletion
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
    label?: string;
    shop_id?: string;
    shop_name?: string;
    tier?: string;
    switch_token?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "bad_request" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);
  const action = body.action ?? "activate";
  const ip = (req.headers.get("x-forwarded-for") ?? "unknown")
    .split(",")[0]
    .trim();

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
  if (action === "create_branch") {
    return handleCreateBranch(admin, userData.user, body.shop_name ?? "");
  }
  if (action === "link_branch") {
    // Accepts an arbitrary key string and reports back whether it was
    // valid — the exact same brute-force surface as the default `activate`
    // action, so it gets the same per-IP rate limit (previously missing:
    // this action could be probed for valid keys with no throttling at all).
    if (!(await checkAndRecordRateLimit(admin, ip))) {
      return json({ ok: false, error: "rate_limited" }, 200);
    }
    return handleLinkBranch(
      admin,
      userData.user,
      body.key ?? "",
      body.label ?? "",
    );
  }
  if (action === "list_branches") {
    return handleListBranches(admin, userData.user);
  }
  if (action === "unlink_branch") {
    return handleUnlinkBranch(admin, userData.user, body.shop_id ?? "");
  }
  if (action === "switch_branch") {
    return handleSwitchBranch(
      admin,
      userData.user,
      body.shop_id ?? "",
      body.switch_token ?? "",
    );
  }
  if (action === "signup_shop") {
    return handleSignupShop(
      admin,
      body.shop_name ?? "",
      body.email ?? "",
      body.password ?? "",
      body.device_id ?? "",
    );
  }
  if (action === "set_tier") {
    return handleSetTier(admin, userData.user, body.tier ?? "");
  }
  if (action === "delete_account") {
    return handleDeleteAccount(
      admin,
      userData.user,
      body.password ?? "",
      supabaseUrl,
      anonKey,
    );
  }

  const key = (body.key ?? "").trim();
  const deviceId = (body.device_id ?? "").trim();
  if (!key || !deviceId) {
    return json({ ok: false, error: "bad_request" }, 400);
  }

  // Rate limit: this action accepts an arbitrary key string and reports back
  // whether it was valid — exactly the surface a brute-force script would
  // target. At most 10 attempts per IP per 15 minutes; counted before the
  // lookup so rapid guesses can't dodge the limit. (`link_branch` shares this
  // same helper — see its dispatch above.)
  if (!(await checkAndRecordRateLimit(admin, ip))) {
    // 200, not 429 — every other soft/business-logic error this action
    // returns (invalid_key, device_mismatch) uses 200 so the client's
    // `res.data` parsing path (not its exception path) handles it.
    return json({ ok: false, error: "rate_limited" }, 200);
  }

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
    tier: license.tier ?? "offline",
  }, 200);
});

// deno-lint-ignore no-explicit-any
type SupabaseUser = any;
// deno-lint-ignore no-explicit-any
type AdminClient = any;

// At most 10 attempts per IP per 15 minutes across every action that accepts
// an arbitrary, guessable key string and reports back whether it was valid
// (`activate`'s default action, and `link_branch`) — recorded before the
// lookup so rapid guesses can't dodge the limit. Returns false when the
// caller should be rejected with `rate_limited`.
async function checkAndRecordRateLimit(
  admin: AdminClient,
  ip: string,
): Promise<boolean> {
  const windowStart = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const { count } = await admin
    .from("activate_attempts")
    .select("id", { count: "exact", head: true })
    .eq("ip", ip)
    .gte("created_at", windowStart);
  if ((count ?? 0) >= 10) return false;
  await admin.from("activate_attempts").insert({ ip });
  return true;
}

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
// Owner-role only. Self-service: switches the CALLER's OWN shop between
// 'offline'/'online' pricing tier. Never touches shop_id, the caller's
// session, or any local data — this only changes which price is suggested
// on the next renewal request (the amount field there stays user-editable
// and admin-reviewed either way, so this isn't a new abuse surface).
async function handleSetTier(
  admin: AdminClient,
  user: SupabaseUser,
  tier: string,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  if (roleOf(user) !== "owner") {
    return json({ ok: false, error: "forbidden" }, 403);
  }
  if (tier !== "offline" && tier !== "online") {
    return json({ ok: false, error: "bad_request" }, 400);
  }

  const { error } = await admin
    .from("licenses")
    .update({ tier, updated_at: new Date().toISOString() })
    .eq("shop_id", shopId);
  if (error) return json({ ok: false, error: "server_error" }, 500);
  return json({ ok: true, tier }, 200);
}

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
  // Every real-login owner always has at least one branch registered: their
  // own shop, labeled "Home". Best-effort — a failure here shouldn't fail
  // account creation; the owner can link it manually via link_branch later.
  await admin.from("org_branches").upsert(
    { owner_user_id: data.user?.id, shop_id: shopId, label: "Home" },
    { onConflict: "owner_user_id,shop_id" },
  );
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

// Owner-role only. Proves the caller actually holds the target branch's key
// (same service-role lookup as the main `activate` flow) before letting them
// register it — otherwise anyone could claim any shop_id as their own
// "branch" just by guessing a shop_id string. Does NOT touch
// `licenses.device_id` — linking is pure bookkeeping, independent of which
// physical device activated that key. Upsert, so re-running it with a new
// label renames the branch.
const BRANCH_TRIAL_MONTHS = 2;

// Owner-role only. Mints a brand new shop_id + trial license (NOT bound to
// any device yet — this branch might not be activated on this physical
// device at all) and auto-links it as a branch the caller owns. This is the
// PRIMARY way to add a branch once already signed in with a real account —
// no separate key round-trip needed, unlike `link_branch` (which stays
// available for the secondary case of an already-existing separate shop).
async function handleCreateBranch(
  admin: AdminClient,
  user: SupabaseUser,
  shopName: string,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  if (roleOf(user) !== "owner") {
    return json({ ok: false, error: "forbidden" }, 403);
  }

  const newShopId = `shop-${crypto.randomUUID().replace(/-/g, "").slice(0, 12)}`;
  const key = "BRANCH-" +
    crypto.randomUUID().replace(/-/g, "").slice(0, 12).toUpperCase();
  const now = new Date();
  const expires = new Date(now);
  expires.setMonth(expires.getMonth() + BRANCH_TRIAL_MONTHS);
  const { data: refCode } = await admin.rpc("gen_referral_code");

  const { data: license, error: licErr } = await admin
    .from("licenses")
    .insert({
      shop_id: newShopId,
      shop_name: shopName || null,
      key,
      plan: "trial",
      status: "active",
      expires_at: expires.toISOString(),
      activated_at: now.toISOString(),
      referral_code: refCode,
      tier: "online",
    })
    .select("shop_id")
    .single();
  if (licErr) return json({ ok: false, error: "server_error" }, 500);

  const { error: linkErr } = await admin.from("org_branches").upsert(
    { owner_user_id: user.id, shop_id: newShopId, label: shopName || null },
    { onConflict: "owner_user_id,shop_id" },
  );
  if (linkErr) return json({ ok: false, error: "server_error" }, 500);

  return json({ ok: true, shop_id: license.shop_id }, 200);
}

async function handleLinkBranch(
  admin: AdminClient,
  user: SupabaseUser,
  key: string,
  label: string,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  if (roleOf(user) !== "owner") {
    return json({ ok: false, error: "forbidden" }, 403);
  }
  const trimmedKey = key.trim();
  if (!trimmedKey) return json({ ok: false, error: "bad_request" }, 400);

  const { data: license, error: licErr } = await admin
    .from("licenses")
    .select("shop_id")
    .eq("key", trimmedKey)
    .maybeSingle();
  if (licErr) return json({ ok: false, error: "server_error" }, 500);
  if (!license) return json({ ok: false, error: "invalid_key" }, 200);

  const { error } = await admin.from("org_branches").upsert(
    {
      owner_user_id: user.id,
      shop_id: license.shop_id,
      label: label.trim() || null,
    },
    { onConflict: "owner_user_id,shop_id" },
  );
  if (error) return json({ ok: false, error: "server_error" }, 500);
  return json({ ok: true, shop_id: license.shop_id }, 200);
}

// Owner-role only. Lists every branch the caller has linked (including their
// own current shop_id, auto-registered at create_shop_login time).
async function handleListBranches(
  admin: AdminClient,
  user: SupabaseUser,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  if (roleOf(user) !== "owner") {
    return json({ ok: false, error: "forbidden" }, 403);
  }

  // Legacy owners may have no org_branches row for their currently active
  // shop. Ensure it exists so "Current branch" never disappears from the list.
  await admin.from("org_branches").upsert(
    { owner_user_id: user.id, shop_id: shopId, label: "Home" },
    { onConflict: "owner_user_id,shop_id", ignoreDuplicates: true },
  );

  const { data, error } = await admin
    .from("org_branches")
    .select("shop_id, label")
    .eq("owner_user_id", user.id)
    .order("created_at", { ascending: true });
  if (error) return json({ ok: false, error: "server_error" }, 500);

  // deno-lint-ignore no-explicit-any
  const rows = (data as any[]) ?? [];
  const branches = rows.map((b) => ({
    shop_id: b.shop_id,
    label: b.label,
    is_current: b.shop_id === shopId,
  }));
  if (!branches.some((b) => b.shop_id === shopId)) {
    branches.unshift({ shop_id: shopId, label: "Home", is_current: true });
  }
  return json({ ok: true, branches }, 200);
}

// Owner-role only. Removes a branch link. No guard against unlinking down to
// zero (including the caller's own current branch) — re-linking is always
// possible with the key.
async function handleUnlinkBranch(
  admin: AdminClient,
  user: SupabaseUser,
  targetShopId: string,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  if (roleOf(user) !== "owner") {
    return json({ ok: false, error: "forbidden" }, 403);
  }
  if (!targetShopId) return json({ ok: false, error: "bad_request" }, 400);

  const { error } = await admin
    .from("org_branches")
    .delete()
    .eq("owner_user_id", user.id)
    .eq("shop_id", targetShopId);
  if (error) return json({ ok: false, error: "server_error" }, 500);
  return json({ ok: true }, 200);
}

// Owner-role only. Re-scopes the CALLER's OWN session to a branch they've
// already linked — the target must appear in their own org_branches rows,
// so an owner can never switch into a shop they don't own. Also looks up the
// target's own license row (read-only, no device_id mutation — switching is
// a "which shop am I viewing" operation, not a re-activation) so the client
// can rebuild its local CachedLicense without a second round trip. The
// client is responsible for wiping+resyncing local data after this succeeds
// — this app's local DB isn't partitioned per shop.
//
// Optional switch_token: when present, successful responses are stored in
// branch_switch_attempts and identical retries replay the same payload
// (no second metadata write). Missing token keeps legacy one-shot behavior
// for older clients.
async function handleSwitchBranch(
  admin: AdminClient,
  user: SupabaseUser,
  targetShopId: string,
  switchToken: string,
): Promise<Response> {
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  if (roleOf(user) !== "owner") {
    return json({ ok: false, error: "forbidden" }, 403);
  }
  if (!targetShopId) return json({ ok: false, error: "bad_request" }, 400);

  const token = (switchToken ?? "").trim();
  if (token) {
    const { data: existing, error: existingErr } = await admin
      .from("branch_switch_attempts")
      .select("response_json, to_shop_id")
      .eq("owner_user_id", user.id)
      .eq("switch_token", token)
      .maybeSingle();
    if (existingErr) return json({ ok: false, error: "server_error" }, 500);
    if (existing?.response_json) {
      return json(existing.response_json as Record<string, unknown>, 200);
    }
  }

  // Self-heal legacy state before any switch: pin the caller's current shop as
  // a branch so they can always switch back later.
  await admin.from("org_branches").upsert(
    { owner_user_id: user.id, shop_id: shopId, label: "Home" },
    { onConflict: "owner_user_id,shop_id", ignoreDuplicates: true },
  );

  // Already scoped to the target — treat as success (idempotent no-op) so a
  // retry after a successful claim but failed client wipe/sync can continue.
  if (shopId === targetShopId) {
    const payload = await licensePayloadForShop(admin, targetShopId);
    if (token) {
      await admin.from("branch_switch_attempts").upsert(
        {
          owner_user_id: user.id,
          switch_token: token,
          from_shop_id: shopId,
          to_shop_id: targetShopId,
          response_json: payload,
        },
        { onConflict: "owner_user_id,switch_token" },
      );
    }
    return json(payload, 200);
  }

  const { data: link, error: linkErr } = await admin
    .from("org_branches")
    .select("shop_id")
    .eq("owner_user_id", user.id)
    .eq("shop_id", targetShopId)
    .maybeSingle();
  if (linkErr) return json({ ok: false, error: "server_error" }, 500);
  if (!link) return json({ ok: false, error: "forbidden" }, 403);

  const { error: metaErr } = await admin.auth.admin.updateUserById(user.id, {
    app_metadata: { shop_id: targetShopId, role: "owner" },
  });
  if (metaErr) return json({ ok: false, error: "server_error" }, 500);

  const payload = await licensePayloadForShop(admin, targetShopId);
  if (token) {
    await admin.from("branch_switch_attempts").upsert(
      {
        owner_user_id: user.id,
        switch_token: token,
        from_shop_id: shopId,
        to_shop_id: targetShopId,
        response_json: payload,
      },
      { onConflict: "owner_user_id,switch_token" },
    );
  }
  return json(payload, 200);
}

async function licensePayloadForShop(
  admin: AdminClient,
  targetShopId: string,
): Promise<Record<string, unknown>> {
  const { data: license } = await admin
    .from("licenses")
    .select("plan, expires_at, realtime_enabled, activated_at, tier")
    .eq("shop_id", targetShopId)
    .order("expires_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  return {
    ok: true,
    shop_id: targetShopId,
    plan: license?.plan ?? "monthly",
    expires_at: license?.expires_at ?? null,
    realtime_enabled: license?.realtime_enabled === true,
    activated_at: license?.activated_at ?? null,
    tier: license?.tier ?? "offline",
  };
}

const SIGNUP_TRIAL_MONTHS = 2;

// The only action that doesn't require a shop to already exist — mints a
// brand new shop_id, a 2-month trial license bound to this device, a real
// owner login, and an auto-registered "Home" branch, all in one call. Does
// NOT touch the calling (anonymous) session at all — the new owner account
// is a completely separate auth user, signed into directly by the client
// afterward, same as `create_shop_login`/`invite_staff` already create
// separate users rather than upgrading the caller in place.
async function handleSignupShop(
  admin: AdminClient,
  shopName: string,
  email: string,
  password: string,
  deviceId: string,
): Promise<Response> {
  if (!email || !password) return json({ ok: false, error: "bad_request" }, 400);

  const shopId = `shop-${crypto.randomUUID().replace(/-/g, "").slice(0, 12)}`;
  const key = "SIGNUP-" +
    crypto.randomUUID().replace(/-/g, "").slice(0, 12).toUpperCase();
  const now = new Date();
  const expires = new Date(now);
  expires.setMonth(expires.getMonth() + SIGNUP_TRIAL_MONTHS);
  const { data: refCode } = await admin.rpc("gen_referral_code");

  const { data: license, error: licErr } = await admin
    .from("licenses")
    .insert({
      shop_id: shopId,
      shop_name: shopName || null,
      key,
      plan: "trial",
      status: "active",
      device_id: deviceId || null,
      expires_at: expires.toISOString(),
      activated_at: now.toISOString(),
      referral_code: refCode,
      tier: "online",
    })
    .select("*")
    .single();
  if (licErr) return json({ ok: false, error: "server_error" }, 500);

  const { data: userRes, error: userErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: { shop_id: shopId, role: "owner" },
  });
  if (userErr) {
    // Roll back the just-created license so a failed signup doesn't leave an
    // orphaned shop_id nothing can ever claim.
    await admin.from("licenses").delete().eq("id", license.id);
    const msg = String(userErr.message ?? "").toLowerCase();
    if (msg.includes("already") || msg.includes("registered")) {
      return json({ ok: false, error: "email_taken" }, 200);
    }
    return json({ ok: false, error: "server_error" }, 500);
  }

  await admin.from("org_branches").upsert(
    { owner_user_id: userRes.user?.id, shop_id: shopId, label: "Home" },
    { onConflict: "owner_user_id,shop_id" },
  );

  return json({
    ok: true,
    shop_id: shopId,
    plan: "trial",
    expires_at: license.expires_at,
    activated_at: license.activated_at,
    tier: "online",
  }, 200);
}

/// Owner-only account deletion (App Store 5.1.1(v) / Play). Re-checks password,
/// wipes shop-scoped cloud rows best-effort, deletes licenses + org links, then
/// deletes Auth users for those shops (staff + owner).
async function handleDeleteAccount(
  admin: AdminClient,
  user: SupabaseUser,
  password: string,
  supabaseUrl: string,
  anonKey: string,
): Promise<Response> {
  if (roleOf(user) !== "owner") {
    return json({ ok: false, error: "forbidden" }, 403);
  }
  const shopId = shopIdOf(user);
  if (!shopId) return json({ ok: false, error: "not_activated" }, 200);
  const email = user.email ?? "";
  if (!email || !password) {
    return json({ ok: false, error: "bad_request" }, 400);
  }

  const verify = createClient(supabaseUrl, anonKey);
  const { error: authErr } = await verify.auth.signInWithPassword({
    email,
    password,
  });
  if (authErr) {
    return json({ ok: false, error: "wrong_password" }, 200);
  }

  const shopIds = new Set<string>([shopId]);
  const { data: branches } = await admin
    .from("org_branches")
    .select("shop_id")
    .eq("owner_user_id", user.id);
  for (const row of branches ?? []) {
    if (row.shop_id) shopIds.add(row.shop_id as string);
  }

  // Leaf → root-ish. Failures are ignored so a missing table never blocks
  // auth deletion (the required privacy outcome).
  const shopTables = [
    "sale_items",
    "payments",
    "credit_payments",
    "order_items",
    "purchase_order_items",
    "stock_movements",
    "stock_levels",
    "sales",
    "orders",
    "purchase_orders",
    "expenses",
    "cash_sessions",
    "supplier_payments",
    "equity_entries",
    "recurring_expenses",
    "license_payments",
    "license_events",
    "license_requests",
    "products",
    "categories",
    "customers",
    "suppliers",
    "staff_members",
    "device_labels",
    "payment_accounts",
    "storefront_blocklist",
    "storefronts",
    "branch_switch_attempts",
    "licenses",
  ];

  for (const sid of shopIds) {
    for (const table of shopTables) {
      try {
        await admin.from(table).delete().eq("shop_id", sid);
      } catch {
        /* best-effort */
      }
    }
    try {
      await admin.from("org_branches").delete().eq("shop_id", sid);
    } catch {
      /* best-effort */
    }
  }

  const { data: listed } = await admin.auth.admin.listUsers({
    page: 1,
    perPage: 1000,
  });
  // deno-lint-ignore no-explicit-any
  const toDelete = ((listed?.users ?? []) as any[]).filter((u) =>
    shopIds.has(shopIdOf(u) ?? "")
  );
  // Delete staff first, owner (caller) last.
  toDelete.sort((a, b) =>
    (a.id === user.id ? 1 : 0) - (b.id === user.id ? 1 : 0)
  );
  for (const u of toDelete) {
    try {
      await admin.auth.admin.deleteUser(u.id);
    } catch {
      /* best-effort */
    }
  }

  return json({ ok: true }, 200);
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
