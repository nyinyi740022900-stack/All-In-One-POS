// Account-only subscription and shop lifecycle. Keys are retained in historical
// records only and cannot provision sessions or devices through this endpoint.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  AccountAdmin,
  accountError,
  accountRole,
  AccountUser,
  hasPremium,
  realAccount,
  resolveAccountShop,
  retiredAccountAction,
  subscriptionReply,
  trustedShopId,
} from "../_shared/account_premium.ts";

import { verifySocialReauthentication } from "./social_reauth.ts";

type Body = Record<string, unknown>;
const value = (body: Body, key: string): string =>
  typeof body[key] === "string" ? (body[key] as string).trim() : "";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
function failure(error: string): Response {
  return json({ ok: false, error }, error === "server_error" ? 500 : 200);
}

export async function handleRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") {
    return json({ ok: false, error: "method_not_allowed" }, 405);
  }
  let body: Body;
  try {
    body = await req.json();
    if (!body || Array.isArray(body) || typeof body !== "object") {
      throw new Error();
    }
  } catch {
    return json({ ok: false, error: "bad_request" }, 400);
  }
  const action = value(body, "action") || "activate";
  const retired = retiredAccountAction(action);
  if (retired) return failure(retired);
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const asUser = createClient(url, anon, {
    global: {
      headers: { Authorization: req.headers.get("Authorization") ?? "" },
    },
  });
  const { data, error } = await asUser.auth.getUser();
  if (error || !data.user) {
    return json({ ok: false, error: "not_authenticated" }, 401);
  }
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  // getUser verified this exact token before we read its signed session binding.
  let sessionId: string | undefined;
  try {
    const jwt =
      (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").split(
        ".",
      )[1];
    sessionId =
      JSON.parse(atob(jwt.replace(/-/g, "+").replace(/_/g, "/"))).session_id;
  } catch {
    return failure("not_authenticated");
  }
  if (!sessionId || !/^[0-9a-f-]{36}$/i.test(sessionId)) {
    return failure("not_authenticated");
  }
  try {
    return await handleAccountAction(
      admin,
      data.user,
      action,
      body,
      url,
      anon,
      sessionId,
    );
  } catch {
    return failure("server_error");
  }
}

export async function handleAccountAction(
  admin: AccountAdmin,
  user: AccountUser,
  action: string,
  body: Body,
  url = "",
  anon = "",
  sessionId?: string,
): Promise<Response> {
  const retired = retiredAccountAction(action);
  if (retired) return failure(retired);
  if (action === "signup_shop") return await signup(admin, user, body);
  // Legacy conversion requires server-assigned owner identity and never a key.
  if (action === "create_shop_login") {
    return await createLegacyLogin(admin, user, body);
  }
  if (!realAccount(user)) return failure("account_required");
  if (action === "prepare_social_account" || action === "signup_social_shop") {
    const creating = action === "signup_social_shop";
    const { data, error } = await admin.rpc(
      creating ? "create_social_account_shop" : "resolve_social_account",
      creating
        ? { p_user_id: user.id, p_shop_name: value(body, "shop_name") }
        : { p_user_id: user.id },
    );
    if (error) return failure(accountError(error));
    if (!creating && data.needs_shop_name === true) {
      return json({ ok: true, needs_shop_name: true });
    }
    const role = creating ? "owner" : data.role;
    const updated = await admin.auth.admin.updateUserById(user.id, {
      app_metadata: { ...user.app_metadata, shop_id: data.shop_id, role },
    });
    if (updated.error) return failure("server_error");
    // Signup does not establish a device binding or issue a Premium receipt.
    // Refresh JWT and register the device through normal account attachment.
    return creating
      ? json(await subscriptionReply(data, user.id, ""))
      : json({ ok: true, needs_shop_name: false, shop_id: data.shop_id });
  }
  if (action === "list_branches") {
    const { data, error } = await admin.from("shop_subscriptions")
      .select("shop_id,shop_name,plan,expires_at,is_archived").eq(
        "owner_user_id",
        user.id,
      );
    if (error) return failure("server_error");
    return json({
      ok: true,
      branches: (data ?? []).map((s: Record<string, unknown>) => ({
        ...s,
        label: s.shop_name ?? "Home",
        is_current: s.shop_id === trustedShopId(user),
      })),
    });
  }
  if (action === "create_branch") {
    const { data: owned, error } = await admin.from("shop_subscriptions")
      .select("shop_id").eq("owner_user_id", user.id).limit(1);
    if (error) return failure("server_error");
    if (!owned?.length) return failure("forbidden");
    const shopId = `shop-${crypto.randomUUID()}`;
    const created = await admin.rpc("create_account_shop", {
      p_user_id: user.id,
      p_shop_id: shopId,
      p_shop_name: value(body, "shop_name"),
      p_device_id: null,
    });
    return created.error
      ? failure(accountError(created.error))
      : json({ ok: true, shop_id: shopId, plan: "free" });
  }
  const shopId = await resolveAccountShop(admin, user, value(body, "shop_id"));
  if (!shopId) return failure("membership_revoked");
  const role = await accountRole(admin, user.id, shopId);
  const deviceId = value(body, "device_id");
  if (
    [
      "refresh_account_license",
      "resync_session",
      "switch_branch",
      "start_trial",
    ].includes(action)
  ) {
    if (!deviceId) return failure("bad_request");
    if (action === "switch_branch" && role !== "owner") {
      return failure("forbidden");
    }
    if (action === "start_trial" && role !== "owner") {
      return failure("forbidden");
    }
    const { data, error } = await admin.rpc(
      action === "start_trial" ? "start_account_trial" : "register_shop_device",
      {
        p_user_id: user.id,
        p_shop_id: shopId,
        p_device_id: deviceId,
        p_reclaim: body.reclaim_device === true,
        p_session_id: sessionId ?? null,
      },
    );
    if (error) return failure(accountError(error));
    const { error: metaError } = await admin.auth.admin.updateUserById(
      user.id,
      {
        app_metadata: { ...user.app_metadata, shop_id: shopId, role },
      },
    );
    if (metaError) return failure("server_error");
    if (role === "owner") {
      await admin.from("org_branches").update({
        last_active_at: new Date().toISOString(),
      }).eq("owner_user_id", user.id).eq("shop_id", shopId);
    }
    // Never replay stored branch receipts: each retry rechecks archive, release,
    // membership and current revision before issuing proof for this device.
    return json(await subscriptionReply(data, user.id, deviceId));
  }
  if (action === "release_device") {
    if (!deviceId) return failure("bad_request");
    const { data, error } = await admin.rpc("release_shop_device", {
      p_user_id: user.id,
      p_shop_id: shopId,
      p_device_id: deviceId,
    });
    return error ? failure(accountError(error)) : json(data);
  }
  if (action === "list_devices") {
    const { data, error } = await admin.from("shop_devices").select(
      "device_id,user_id,registered_at,last_active_at,released_at",
    ).eq("shop_id", shopId).order("registered_at");
    return error ? failure("server_error") : json({
      ok: true,
      shop_id: shopId,
      devices: data ?? [],
      device_limit: 3,
    });
  }
  if (role !== "owner") return failure("forbidden");
  if (action === "unlink_branch") {
    // Unlinking would hide billing/account recovery for an owned shop. Ownership
    // changes need an explicit support transfer, not deleting a navigation row.
    return failure("ownership_transfer_required");
  }
  if (action === "invite_staff") {
    const { data: subscription, error } = await admin.from("shop_subscriptions")
      .select("*").eq("shop_id", shopId).single();
    if (error) return failure("server_error");
    if (!hasPremium(subscription)) return failure("premium_required");
    const email = value(body, "email"),
      password = typeof body.password === "string" ? body.password : "";
    if (!email || !password) return failure("bad_request");
    const created = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      app_metadata: { shop_id: shopId, role: "staff" },
    });
    return created.error
      ? failure(authError(created.error))
      : json({ ok: true, user_id: created.data.user.id, email });
  }
  if (action === "revoke_staff") {
    const targetId = value(body, "user_id");
    if (!targetId || await accountRole(admin, targetId, shopId) !== "staff") {
      return failure("forbidden");
    }
    const { error } = await admin.auth.admin.updateUserById(targetId, {
      ban_duration: "876000h",
    });
    if (error) return failure("server_error");
    const { error: deviceError } = await admin.from("shop_devices").update({
      released_at: new Date().toISOString(),
    }).eq("shop_id", shopId).eq("user_id", targetId);
    return deviceError ? failure("server_error") : json({ ok: true });
  }
  if (action === "list_staff") {
    const users = await allUsers(admin);
    return json({
      ok: true,
      staff: users.filter((u) =>
        trustedShopId(u) === shopId && u.app_metadata?.role === "staff"
      ).map((u) => ({
        user_id: u.id,
        email: u.email,
        banned: !!u.banned_until && Date.parse(u.banned_until) > Date.now(),
      })),
    });
  }
  if (action === "delete_account") {
    return await deleteAccount(admin, user, body, url, anon);
  }
  return failure("unknown_action");
}
function authError(error: { message?: string }): string {
  return /already|registered/i.test(error.message ?? "")
    ? "email_taken"
    : "server_error";
}
async function signup(
  admin: AccountAdmin,
  caller: AccountUser,
  body: Body,
): Promise<Response> {
  const deviceId = value(body, "device_id");
  if (!deviceId) return failure("bad_request");
  // An authenticated account must not bypass staff/revocation/idempotency
  // checks by choosing the old password-signup action instead of social signup.
  // Anonymous email/password signup below still creates its new Auth owner.
  if (realAccount(caller)) {
    return await handleAccountAction(admin, caller, "signup_social_shop", body);
  }
  const shopId = `shop-${crypto.randomUUID()}`;
  let owner = caller;
  let createdUser = false;
  if (!realAccount(caller)) {
    const email = value(body, "email"),
      password = typeof body.password === "string" ? body.password : "";
    if (!email || !password) return failure("bad_request");
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      app_metadata: { role: "owner", shop_id: shopId },
    });
    if (error) return failure(authError(error));
    owner = data.user;
    createdUser = true;
  }
  const { data, error } = await admin.rpc("create_account_shop", {
    p_user_id: owner.id,
    p_shop_id: shopId,
    p_shop_name: value(body, "shop_name"),
    p_device_id: deviceId,
  });
  if (error) {
    if (createdUser) await admin.auth.admin.deleteUser(owner.id);
    return failure(accountError(error));
  }
  const updated = await admin.auth.admin.updateUserById(owner.id, {
    app_metadata: { ...owner.app_metadata, role: "owner", shop_id: shopId },
  });
  if (updated.error) return failure("server_error");
  return json(await subscriptionReply(data, owner.id, deviceId));
}
async function createLegacyLogin(
  admin: AccountAdmin,
  user: AccountUser,
  body: Body,
): Promise<Response> {
  const shopId = trustedShopId(user);
  // Legacy anonymous key/trial sessions with no trusted owner role require
  // support verification. Public device IDs never establish ownership.
  if (!shopId || user.app_metadata?.role !== "owner") {
    return failure("ownership_verification_required");
  }
  const email = value(body, "email"),
    password = typeof body.password === "string" ? body.password : "";
  if (!email || !password) return failure("bad_request");
  const { data: subscription, error } = await admin.from("shop_subscriptions")
    .select("owner_user_id").eq("shop_id", shopId).single();
  if (error) return failure("server_error");
  if (subscription.owner_user_id) return failure("account_already_linked");
  const created = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: { shop_id: shopId, role: "owner" },
  });
  if (created.error) return failure(authError(created.error));
  const attached = await admin.rpc("attach_legacy_shop_owner", {
    p_legacy_user_id: user.id,
    p_owner_user_id: created.data.user.id,
    p_shop_id: shopId,
  });
  if (attached.error) {
    await admin.auth.admin.deleteUser(created.data.user.id);
    return failure(accountError(attached.error));
  }
  return json({
    ok: true,
    user_id: created.data.user.id,
    shop_id: shopId,
    email,
  });
}
// deno-lint-ignore no-explicit-any
async function allUsers(admin: AccountAdmin): Promise<any[]> {
  const result = [];
  for (let page = 1;; page++) {
    const { data, error } = await admin.auth.admin.listUsers({
      page,
      perPage: 1000,
    });
    if (error) throw new Error("server_error");
    result.push(...data.users);
    if (data.users.length < 1000) return result;
  }
}
export async function deleteExistingShopRows(
  admin: AccountAdmin,
  ids: Set<string>,
): Promise<boolean> {
  const tables = [
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
    "cash_top_ups",
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
    "staff_permissions",
    "staff_members",
    "device_labels",
    "payment_accounts",
    "storefront_blocklist",
    "storefronts",
    "shop_profiles",
    "shop_devices",
    "org_branches",
    "licenses",
  ];
  for (const id of ids) {
    for (const table of tables) {
      const { error } = await admin.from(table).delete().eq("shop_id", id);
      if (error) return false;
    }
  }
  return true;
}
async function deleteAccount(
  admin: AccountAdmin,
  user: AccountUser,
  body: Body,
  url: string,
  anon: string,
): Promise<Response> {
  const password = typeof body.password === "string" ? body.password : "";
  if (body.provider !== undefined) {
    const accepted = await verifySocialReauthentication(
      user.id,
      body,
      async (proof) => {
        // Never share the app's bearer/session with provider reauthentication.
        const verifier = createClient(url, anon, {
          auth: {
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUrl: false,
          },
          global: {
            fetch: (input, init) =>
              fetch(input, { ...init, signal: AbortSignal.timeout(15000) }),
          },
        });
        const { data, error } = await verifier.auth.signInWithIdToken(proof);
        const verifiedId = error ? null : data.user?.id ?? null;
        if (data.session) await verifier.auth.signOut({ scope: "local" });
        return verifiedId;
      },
      async (hash, expiresAt) => {
        const { data, error } = await admin.rpc("consume_social_reauth_proof", {
          p_user_id: user.id,
          p_proof_hash: hash,
          p_expires_at: expiresAt,
        });
        return !error && data === true;
      },
    );
    if (!accepted) return failure("social_reauth_failed");
  } else {
    if (!password || !user.email) return failure("bad_request");
    const { data, error: authError } = await createClient(url, anon).auth
      .signInWithPassword({ email: user.email, password });
    if (authError || data.user?.id !== user.id) {
      return failure("wrong_password");
    }
  }
  const { data, error } = await admin.from("shop_subscriptions").select(
    "shop_id",
  ).eq("owner_user_id", user.id);
  if (error) return failure("server_error");
  const ids = new Set<string>(
    (data ?? []).map((s: { shop_id: string }) => s.shop_id),
  );
  // Archive first so retries cannot authorize new work while deletion proceeds.
  for (const id of ids) {
    const archive = await admin.from("shop_subscriptions").update({
      is_archived: true,
    }).eq("shop_id", id);
    if (archive.error) return failure("server_error");
  }
  const users = await allUsers(admin);
  if (!await deleteExistingShopRows(admin, ids)) return failure("server_error");
  for (const target of users) {
    if (
      target.id !== user.id && target.app_metadata?.role === "staff" &&
      ids.has(trustedShopId(target) ?? "")
    ) {
      const deleted = await admin.auth.admin.deleteUser(target.id);
      if (deleted.error) return failure("server_error");
    }
  }
  const deleted = await admin.auth.admin.deleteUser(user.id);
  return deleted.error ? failure("server_error") : json({ ok: true });
}
if (import.meta.main) Deno.serve(handleRequest);
