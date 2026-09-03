// Edge Function: admin console backend.
//
// One authenticated endpoint for the vendor admin dashboard. Verifies the
// caller is an admin (JWT app_metadata.role === 'admin'), then performs the
// requested action with the service role. Keeps the service key server-side —
// the web dashboard only ever holds the anon key + an admin session.
//
// Actions (POST body { action, ... }):
//   list_licenses                         -> licenses (newest first)
//   list_shops                            -> one row per shop (devices + accounts)
//   lookup_shop { email|device_id|shop_id } -> one shop (fresh, for extend preview)
//   reset_password { email }              -> { action_link } recovery URL
//   unlink_account { user_id }            -> clear shop_id on a staff (or extra owner)
//   restore_account { user_id }           -> lift a revoke_staff ban
//   create_license { shop_id, plan, months } -> { key }
//   set_device_allowance { shop_id, extra_slots, months } -> { extra_slots, extras_expires_at }
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
    extra_slots?: number;
    key?: string;
    device_id?: string;
    email?: string;
    request_id?: string;
    reason?: string;
    user_id?: string;
    id?: string;
    // deno-lint-ignore no-explicit-any
    carrier?: any;
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

    case "list_shops": {
      // One row per shop, merged from three sources that only overlap on
      // shop_id: licenses (name/plan/status — the common case, but NOT
      // guaranteed: an auth.users row can outlive its license, see below),
      // storefronts (phone/address — only shops that opted into the public
      // storefront feature), and auth.users (email — lives only in Auth,
      // never in a table; matched via app_metadata.shop_id, the same claim
      // auth_shop_id() reads for RLS).
      const { data: licRows, error: licErr } = await admin
        .from("licenses")
        .select(
          "key, shop_id, shop_name, plan, status, expires_at, tier, device_id, updated_at",
        )
        .eq("is_deleted", false)
        .order("updated_at", { ascending: false })
        .limit(2000);
      if (licErr) return json({ error: "server_error" }, 500);

      // A shop can have multiple device rows (0025_multi_device_licensing.sql)
      // — keep the most recently updated one per shop_id for the shop-level
      // status/plan/expiry, and retain every row under `devices` so the
      // admin 360 view can reset a specific phone.
      // deno-lint-ignore no-explicit-any
      const shops = new Map<string, any>();
      // deno-lint-ignore no-explicit-any
      const devicesByShop = new Map<string, any[]>();
      for (const r of (licRows ?? [])) {
        if (!shops.has(r.shop_id)) shops.set(r.shop_id, { ...r });
        const list = devicesByShop.get(r.shop_id) ?? [];
        list.push({
          key: r.key,
          device_id: r.device_id ?? null,
          status: r.status,
          expires_at: r.expires_at,
          plan: r.plan,
        });
        devicesByShop.set(r.shop_id, list);
      }

      const { data: storeRows } = await admin
        .from("storefronts")
        .select("shop_id, phone, address");
      const storeByShop = new Map<string, { phone: string | null; address: string | null }>();
      for (const s of (storeRows ?? [])) {
        storeByShop.set(s.shop_id, { phone: s.phone, address: s.address });
      }

      // shop_profiles mirrors ShopProfileScreen's contact fields for every
      // shop, not just ones that opted into a public Storefront — the
      // fallback source for phone/address/name. Storefront wins when both
      // exist: it's the customer-facing, deliberately-published version,
      // which can differ from what's saved on the receipt-header profile.
      const { data: profileRows } = await admin
        .from("shop_profiles")
        .select("shop_id, name, phone, address")
        .eq("is_deleted", false);
      const profileByShop = new Map<
        string,
        { name: string | null; phone: string | null; address: string | null }
      >();
      for (const p of (profileRows ?? [])) {
        profileByShop.set(p.shop_id, {
          name: p.name,
          phone: p.phone,
          address: p.address,
        });
      }

      // No query-by-metadata filter on the Admin Auth API — a single page is
      // enough at this app's SME scale (same precedent as list_licenses's
      // own limit(2000) / handleListStaff's limit(1000) in activate/index.ts,
      // not built to paginate an unbounded user base).
      const emailByShop = new Map<string, { email: string; role: string | null }>();
      // deno-lint-ignore no-explicit-any
      const accountsByShop = new Map<string, any[]>();
      const { data: userPage } = await admin.auth.admin.listUsers({
        page: 1,
        perPage: 2000,
      });
      // deno-lint-ignore no-explicit-any
      for (const u of ((userPage?.users ?? []) as any[])) {
        const meta = u.app_metadata as Record<string, unknown> | null;
        const sid = meta?.shop_id as string | undefined;
        if (!sid) continue;
        const role = (meta?.role as string | undefined) ?? null;
        if (role === "admin") continue;
        const bannedUntil = u.banned_until as string | null | undefined;
        const banned = !!bannedUntil && new Date(bannedUntil) > new Date();
        const account = {
          id: u.id,
          email: u.email ?? "",
          role,
          last_sign_in_at: u.last_sign_in_at ?? null,
          banned,
        };
        const list = accountsByShop.get(sid) ?? [];
        list.push(account);
        accountsByShop.set(sid, list);
        const existing = emailByShop.get(sid);
        // Prefer the owner's email when a shop has multiple linked users
        // (owner + invited staff).
        if (!existing || role === "owner") {
          emailByShop.set(sid, { email: u.email ?? "", role });
        }
      }

      // A real login account can outlive its license (e.g. a shop whose
      // license row was removed — a data wipe, a manual cleanup — while its
      // auth.users row and app_metadata.shop_id claim were deliberately
      // kept). Without this, such a shop is invisible here even though it's
      // fully reachable and broken for the owner: nothing to extend, only
      // to create fresh. Surface it with null license fields rather than
      // silently dropping it.
      for (const [sid] of emailByShop) {
        if (!shops.has(sid)) {
          shops.set(sid, {
            shop_id: sid,
            shop_name: null,
            plan: null,
            status: "no_license",
            expires_at: null,
            tier: null,
          });
        }
      }

      const { data: allowRows } = await admin
        .from("shop_device_allowance")
        .select("shop_id, extra_slots, extras_expires_at");
      const allowByShop = new Map<
        string,
        { extra_slots: number; extras_expires_at: string | null }
      >();
      for (const a of (allowRows ?? []) as Array<{
        shop_id: string;
        extra_slots: number;
        extras_expires_at: string | null;
      }>) {
        allowByShop.set(a.shop_id, {
          extra_slots: a.extra_slots,
          extras_expires_at: a.extras_expires_at,
        });
      }

      const rows = Array.from(shops.values()).map((r) => {
        const store = storeByShop.get(r.shop_id);
        const profile = profileByShop.get(r.shop_id);
        const em = emailByShop.get(r.shop_id);
        const accounts = accountsByShop.get(r.shop_id) ?? [];
        return {
          shop_id: r.shop_id,
          shop_name: r.shop_name ?? profile?.name ?? null,
          plan: r.plan,
          status: r.status,
          expires_at: r.expires_at,
          tier: r.tier,
          phone: store?.phone ?? profile?.phone ?? null,
          address: store?.address ?? profile?.address ?? null,
          email: em?.email ?? null,
          accounts,
          account_count: accounts.length,
          devices: devicesByShop.get(r.shop_id) ?? [],
          extra_slots: allowByShop.get(r.shop_id)?.extra_slots ?? 0,
          extras_expires_at: allowByShop.get(r.shop_id)?.extras_expires_at ??
            null,
        };
      });
      return json({ rows });
    }

    case "lookup_shop": {
      const dev = (body.device_id ?? "").trim();
      const email = (body.email ?? "").trim().toLowerCase();
      const sidArg = (body.shop_id ?? "").trim();
      if (!dev && !email && !sidArg) return json({ error: "bad_request" }, 400);

      let shopId = sidArg || null;
      if (!shopId && dev) {
        const { data, error } = await admin
          .from("licenses")
          .select("shop_id")
          .eq("device_id", dev)
          .maybeSingle();
        if (error) return json({ error: "server_error" }, 500);
        shopId = data?.shop_id ?? null;
      }
      if (!shopId && email) {
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
      if (!shopId) return json({ error: "not_found" }, 404);

      const { data: licRows, error: licErr } = await admin
        .from("licenses")
        .select(
          "key, shop_id, shop_name, plan, status, expires_at, tier, device_id, updated_at",
        )
        .eq("shop_id", shopId)
        .eq("is_deleted", false)
        .order("updated_at", { ascending: false });
      if (licErr) return json({ error: "server_error" }, 500);
      const primary = (licRows ?? [])[0] ?? null;

      const { data: store } = await admin
        .from("storefronts")
        .select("phone, address")
        .eq("shop_id", shopId)
        .maybeSingle();
      const { data: profile } = await admin
        .from("shop_profiles")
        .select("name, phone, address")
        .eq("shop_id", shopId)
        .eq("is_deleted", false)
        .maybeSingle();

      const { data: userPage } = await admin.auth.admin.listUsers({
        page: 1,
        perPage: 2000,
      });
      // deno-lint-ignore no-explicit-any
      const accounts = ((userPage?.users ?? []) as any[])
        .filter((u) => {
          const meta = u.app_metadata as Record<string, unknown> | null;
          return (meta?.shop_id as string | undefined) === shopId &&
            meta?.role !== "admin";
        })
        .map((u) => {
          const meta = u.app_metadata as Record<string, unknown> | null;
          const bannedUntil = u.banned_until as string | null | undefined;
          return {
            id: u.id,
            email: u.email ?? "",
            role: (meta?.role as string | undefined) ?? null,
            last_sign_in_at: u.last_sign_in_at ?? null,
            banned: !!bannedUntil && new Date(bannedUntil) > new Date(),
          };
        });
      const owner = accounts.find((a) => a.role === "owner") ?? accounts[0];

      if (!primary && accounts.length === 0) {
        return json({ error: "not_found" }, 404);
      }

      return json({
        shop: {
          shop_id: shopId,
          shop_name: primary?.shop_name ?? profile?.name ?? null,
          plan: primary?.plan ?? null,
          status: primary?.status ?? "no_license",
          expires_at: primary?.expires_at ?? null,
          tier: primary?.tier ?? null,
          phone: store?.phone ?? profile?.phone ?? null,
          address: store?.address ?? profile?.address ?? null,
          email: owner?.email ?? null,
          accounts,
          account_count: accounts.length,
          devices: (licRows ?? []).map((r) => ({
            key: r.key,
            device_id: r.device_id ?? null,
            status: r.status,
            expires_at: r.expires_at,
            plan: r.plan,
          })),
        },
      });
    }

    case "reset_password": {
      // Recovery link the admin copies onto Viber — this product does not
      // send transactional email (signup is email_confirm: true for the
      // same reason: SMTP would strand a shop on opening day).
      const email = (body.email ?? "").trim().toLowerCase();
      if (!email) return json({ error: "bad_request" }, 400);
      const { data, error } = await admin.auth.admin.generateLink({
        type: "recovery",
        email,
      });
      if (error) {
        const msg = error.message ?? "";
        if (msg.toLowerCase().includes("not found") ||
          msg.toLowerCase().includes("unable to find")) {
          return json({ error: "not_found" }, 404);
        }
        return json({ error: "server_error", detail: msg }, 500);
      }
      const props = (data as { properties?: { action_link?: string } })
        ?.properties;
      const link = props?.action_link ?? "";
      if (!link) return json({ error: "server_error" }, 500);
      return json({ email, action_link: link });
    }

    case "unlink_account": {
      const userId = (body.user_id ?? "").trim();
      if (!userId) return json({ error: "bad_request" }, 400);
      const { data: target, error: getErr } = await admin.auth.admin
        .getUserById(userId);
      if (getErr || !target?.user) return json({ error: "not_found" }, 404);
      const meta =
        (target.user.app_metadata as Record<string, unknown> | null) ?? {};
      const role = (meta.role as string | undefined) ?? "";
      const shopId = (meta.shop_id as string | undefined) ?? "";
      if (role === "admin") return json({ error: "cannot_unlink_admin" }, 403);
      if (!shopId) return json({ error: "not_found" }, 404);

      if (role === "owner") {
        const { data: userPage } = await admin.auth.admin.listUsers({
          page: 1,
          perPage: 2000,
        });
        // deno-lint-ignore no-explicit-any
        const owners = ((userPage?.users ?? []) as any[]).filter((u) => {
          const m = u.app_metadata as Record<string, unknown> | null;
          return (m?.shop_id as string | undefined) === shopId &&
            m?.role === "owner" &&
            u.id !== userId;
        });
        if (owners.length === 0) return json({ error: "last_owner" }, 400);
      }

      const { error } = await admin.auth.admin.updateUserById(userId, {
        app_metadata: { ...meta, shop_id: "", role: "" },
      });
      if (error) {
        return json({ error: "server_error", detail: error.message }, 500);
      }
      return json({ ok: true });
    }

    case "restore_account": {
      // Inverse of activate's revoke_staff (ban_duration ~100 years).
      const userId = (body.user_id ?? "").trim();
      if (!userId) return json({ error: "bad_request" }, 400);
      const { data: target, error: getErr } = await admin.auth.admin
        .getUserById(userId);
      if (getErr || !target?.user) return json({ error: "not_found" }, 404);
      const { error } = await admin.auth.admin.updateUserById(userId, {
        ban_duration: "none",
      });
      if (error) {
        return json({ error: "server_error", detail: error.message }, 500);
      }
      return json({ ok: true });
    }

    case "extend_license": {
      // Extend whatever license matches an App Reference ID (device_id —
      // a specific device) or an email (the shop's account — matches any
      // of its devices, resolved via app_metadata.shop_id same as
      // list_shops/storefront's own email lookup). At least one required;
      // device_id is tried first since it names an exact license row,
      // email only a shop.
      const dev = (body.device_id ?? "").trim();
      const email = (body.email ?? "").trim().toLowerCase();
      const months = body.months ?? 1;
      if (!dev && !email) return json({ error: "bad_request" }, 400);

      // deno-lint-ignore no-explicit-any
      let lic: any = null;
      if (dev) {
        const { data, error: findErr } = await admin
          .from("licenses")
          .select("key, shop_id, shop_name")
          .eq("device_id", dev)
          .maybeSingle();
        if (findErr) return json({ error: "server_error" }, 500);
        lic = data;
      }

      let shopId: string | null = lic?.shop_id ?? null;
      if (!lic && email) {
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
        if (!shopId) return json({ error: "not_found" }, 404);

        const { data, error: findErr } = await admin
          .from("licenses")
          .select("key, shop_id, shop_name")
          .eq("shop_id", shopId)
          .order("updated_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (findErr) return json({ error: "server_error" }, 500);
        lic = data;
      }

      if (!lic && !shopId) return json({ error: "not_found" }, 404);

      // Guard against a double-click / two-tab race on this manual admin
      // action — unlike fulfill_request (an atomic pending->processing claim
      // on a request row), extend_license has no natural row to claim before
      // minting. An identical extend already logged for this exact key in
      // the last 10 seconds is almost certainly the same click landing twice
      // (slow network + impatience, or two open admin tabs), not two
      // genuinely separate intended extensions. (Scoped to the `lic` branch
      // only — license_events has no shop_id column, only `key`, so the rare
      // zero-license-rows mint-fresh branch below has no matching key yet to
      // guard on.)
      if (lic) {
        const recentDupeWindow = new Date(Date.now() - 10_000).toISOString();
        const { data: recent } = await admin
          .from("license_events")
          .select("expires_at")
          .eq("key", lic.key)
          .eq("action", "extend")
          .eq("months", months)
          .gte("created_at", recentDupeWindow)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (recent) {
          return json({
            expires_at: recent.expires_at,
            key: lic.key,
            created: false,
            duplicate: true,
          });
        }
      }

      // A resolved shop with a real account but zero license rows (e.g. one
      // removed by a data cleanup while the login was deliberately kept) has
      // nothing to renew — mint fresh instead of failing.
      if (!lic) {
        const { data: newKey, error: createErr } = await admin.rpc(
          "create_license",
          { p_shop_id: shopId, p_plan: "monthly", p_months: months },
        );
        if (createErr) {
          return json({ error: "server_error", detail: createErr.message }, 500);
        }
        const { data: created } = await admin
          .from("licenses")
          .select("expires_at")
          .eq("key", newKey)
          .maybeSingle();
        await logEvent(admin, {
          device_id: dev || null,
          shop_name: null,
          key: newKey,
          action: "extend",
          months,
          expires_at: created?.expires_at,
        });
        return json({
          expires_at: created?.expires_at,
          key: newKey,
          created: true,
        });
      }

      const { data, error } = await admin.rpc("renew_license", {
        p_key: lic.key,
        p_months: months,
      });
      if (error) return json({ error: "server_error", detail: error.message }, 500);
      await logEvent(admin, {
        device_id: dev || null,
        shop_name: lic.shop_name,
        key: lic.key,
        action: "extend",
        months,
        expires_at: data,
      });
      return json({ expires_at: data, key: lic.key, created: false });
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

      // Resolve each request's matched shop_id (stamped by the public
      // /renew form's unverified email->account lookup, or by an
      // already-signed-in app) to that shop's ACTUAL registered name, so
      // the admin can spot a request typed under one shop_name that
      // actually resolved to a DIFFERENT shop (email typo, or someone
      // else's account email) before hitting "Confirm payment" — the email
      // field has no ownership proof, so this resolved name is the
      // reviewer's only real cross-check.
      const shopIds = Array.from(
        new Set(
          (data ?? [])
            .map((r) => `${r.shop_id ?? ""}`.trim())
            .filter((id) => id.length > 0),
        ),
      );
      const resolvedNames = new Map<string, string>();
      if (shopIds.length > 0) {
        const { data: licRows } = await admin
          .from("licenses")
          .select("shop_id, shop_name")
          .in("shop_id", shopIds);
        for (const r of licRows ?? []) {
          if (r.shop_name && !resolvedNames.has(r.shop_id)) {
            resolvedNames.set(r.shop_id, r.shop_name as string);
          }
        }
      }
      const rows = (data ?? []).map((r) => ({
        ...r,
        resolved_shop_name: resolvedNames.get(`${r.shop_id ?? ""}`.trim()) ??
          null,
      }));
      return json({ rows });
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

      // Idempotency: atomically claim this request (pending -> processing)
      // BEFORE minting/extending anything. renew_license/create_license are
      // not idempotent — a double "Confirm payment" click, a retried call
      // after a perceived timeout, or two admin tabs open on the same
      // request must not both mint/extend for one payment. Only the caller
      // that wins this conditional update proceeds; every other caller sees
      // `already_fulfilled` immediately. If the mint below fails, the claim
      // is released back to "pending" so the request can be retried instead
      // of getting stuck at "processing" forever.
      const { data: claimed, error: claimErr } = await admin
        .from("license_requests")
        .update({ status: "processing", updated_at: new Date().toISOString() })
        .eq("id", reqId)
        .eq("status", "pending")
        .select("id")
        .maybeSingle();
      if (claimErr) return json({ error: "server_error" }, 500);
      if (!claimed) return json({ error: "already_fulfilled" }, 409);

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

      // Releases this request's claim back to "pending" so a failed mint can
      // be retried through the normal admin flow instead of getting stuck at
      // "processing" forever with no license actually extended.
      const releaseClaim = () =>
        admin
          .from("license_requests")
          .update({ status: "pending" })
          .eq("id", reqId);

      let key: string;
      let referredShopId: string;
      let expiresAt: string | null = null;
      let action: string;
      if (existing?.key) {
        const { data, error } = await admin.rpc("renew_license", {
          p_key: existing.key,
          p_months: months,
        });
        if (error) {
          await releaseClaim();
          return json({ error: "server_error", detail: error.message }, 500);
        }
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
        if (mkErr) {
          await releaseClaim();
          return json({ error: "server_error", detail: mkErr.message }, 500);
        }
        key = newKey as string;
        referredShopId = shopId;
        action = "issue";
      }

      // The license is already minted at this point (create_license/
      // renew_license above committed) — this status flip is bookkeeping on
      // top of that. If it silently fails, the request row stays "pending"
      // and a second "Confirm payment" click would mint/extend AGAIN for the
      // same shop (create_license has no shop_id uniqueness guard), so the
      // caller must be told this didn't fully succeed rather than getting a
      // response indistinguishable from a clean fulfill.
      const { error: markErr } = await admin
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
      if (markErr) {
        return json({
          key,
          action,
          request_marked_fulfilled: false,
          detail: markErr.message,
        });
      }
      return json({ key, action, request_marked_fulfilled: true });
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

      // Nothing irreversible has happened yet (no license minted for a
      // rejection), unlike fulfill_request above — so unlike there, it's
      // safe to hard-fail here on an update error rather than reporting a
      // partial success; the admin is told to retry instead of believing
      // the request was declined when the row is actually still pending.
      const { error: updateErr } = await admin
        .from("license_requests")
        .update({
          status: "rejected",
          reject_reason: reason || null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", reqId);
      if (updateErr) {
        return json({ error: "server_error", detail: updateErr.message }, 500);
      }
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

      // create_license has no shop_id uniqueness guard at the DB level (a
      // plain insert) — this is the FAB "Generate key" path, reachable for
      // ANY shop_id an admin types in, unlike the Shops-tab button which is
      // only ever shown for rows already known to have status: 'no_license'.
      // Guard here so typing in a shop_id that already has an active
      // license can't silently mint a second live license row for it.
      const { data: existingLic, error: existErr } = await admin
        .from("licenses")
        .select("key")
        .eq("shop_id", shopId)
        .eq("is_deleted", false)
        .limit(1)
        .maybeSingle();
      if (existErr) return json({ error: "server_error" }, 500);
      if (existingLic) return json({ error: "license_already_exists" }, 400);

      const { data, error } = await admin.rpc("create_license", {
        p_shop_id: shopId,
        p_plan: plan,
        p_months: months,
        p_shop_name: (body.shop_name ?? "").trim() || null,
      });
      if (error) return json({ error: "server_error", detail: error.message }, 500);
      return json({ key: data });
    }

    case "set_device_allowance": {
      // Paid extras on top of the free 3 (main phone + 2). No key — the
      // extra phone signs in and taps Check for renewal.
      const shopId = (body.shop_id ?? "").trim();
      const extraSlots = Number(body.extra_slots ?? 0);
      const months = Number(body.months ?? 0);
      if (!shopId) return json({ error: "bad_request" }, 400);
      if (!Number.isFinite(extraSlots) || extraSlots < 0 || extraSlots !== Math.trunc(extraSlots)) {
        return json({ error: "bad_request" }, 400);
      }
      const { data, error } = await admin.rpc("set_shop_device_allowance", {
        p_shop_id: shopId,
        p_extra_slots: extraSlots,
        p_months: extraSlots === 0 ? 1 : months,
      });
      if (error) {
        const detail = error.message ?? "";
        if (detail.includes("must be")) {
          return json({ error: "bad_request", detail }, 400);
        }
        return json({ error: "server_error", detail }, 500);
      }
      const payload = (typeof data === "string" ? JSON.parse(data) : data) as {
        extra_slots?: number;
        extras_expires_at?: string | null;
      } | null;
      await logEvent(admin, {
        device_id: null,
        shop_name: null,
        key: null,
        action: "device_allowance",
        months: extraSlots === 0 ? 0 : months,
      });
      return json({
        extra_slots: payload?.extra_slots ?? extraSlots,
        extras_expires_at: payload?.extras_expires_at ?? null,
      });
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
