// Edge Function: admin console backend.
//
// One authenticated endpoint for the vendor admin dashboard. Verifies the
// caller is an admin (JWT app_metadata.role === 'admin'), then performs the
// requested action with the service role. Keeps the service key server-side —
// the web dashboard only ever holds the anon key + an admin session.
//
// Subscriptions and devices are authoritative; manual payment and admin
// renewals use transactional RPCs with stable payment identities.
// Legacy issuance and extra-device actions return retired_path.

import {
  createClient,
  type User,
} from "https://esm.sh/@supabase/supabase-js@2";
import { subscriptionStatus } from "../_shared/account_premium.ts";

/// Longest licence term any single admin action may grant, in months.
///
/// Three years is far beyond anything sold (plans are monthly or yearly) and
/// exists to catch a typed digit, not to express a product limit.
const MAX_LICENCE_MONTHS = 12;

/// The only keys `set_config` may write.
///
/// Everything in `app_config` is public by design — migration 0006 gives it
/// `for select to anon, authenticated using (true)` so a shop that has not
/// signed in yet can still read the payment instructions. Each key below was
/// chosen with that in mind; nothing secret belongs here, and this list is
/// what stops something secret arriving by accident.
///
/// Keep in step with `kAdminConfigKeys` in `lib/admin/admin_config_keys.dart`
/// — `admin_config_keys_test.dart` fails if the two drift, or if the app
/// starts reading a key the admin cannot set.
const PUBLIC_CONFIG_KEYS = new Set([
  "pay.kbzpay.name",
  "pay.kbzpay.number",
  "pay.wavepay.name",
  "pay.wavepay.number",
  "support.viber",
  "pay.lemonsqueezy.variant_monthly",
  "pay.lemonsqueezy.variant_yearly",
]);

/// Validates a caller-supplied month count, returning it or an error string.
/// Rejects rather than silently clamping — quietly turning a requested 120
/// into 36 would leave the admin believing they granted ten years.
function checkMonths(value: unknown): { months: number } | { error: string } {
  const months = Number(value);
  if (!Number.isInteger(months) || months < 1) {
    return { error: "months_invalid" };
  }
  if (months > MAX_LICENCE_MONTHS) return { error: "months_too_large" };
  if (months !== 1 && months !== 12) return { error: "months_invalid" };
  return { months };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return cors(new Response(null, { status: 204 }));
  }
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
    archived?: boolean;
    config?: Record<string, string>;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);

  if (["create_license", "set_device_allowance"].includes(body.action ?? "")) {
    return json({ error: "retired_path" }, 410);
  }

  switch (body.action) {
    case "list_licenses": {
      const { data, error } = await admin.from("shop_devices").select(
        "shop_id, device_id, user_id, released_at, last_active_at",
      );
      if (error) return json({ error: "server_error" }, 500);
      return json({ rows: (data ?? []).filter((d) => !d.released_at) });
    }
    case "list_shops":
    case "lookup_shop": {
      const { data: subscriptions, error } = await admin.from(
        "shop_subscriptions",
      ).select("*")
        .eq("is_archived", body.archived === true);
      if (error) return json({ error: "server_error" }, 500);
      const { data: profiles, error: profileError } = await admin.from(
        "shop_profiles",
      ).select("shop_id, name, phone, address");
      const { data: devices, error: deviceError } = await admin.from(
        "shop_devices",
      ).select("*").is("released_at", null);
      if (profileError || deviceError) {
        return json({ error: "server_error" }, 500);
      }
      const users: User[] = [];
      for (let page = 1;; page++) {
        const { data, error: userError } = await admin.auth.admin.listUsers({
          page,
          perPage: 1000,
        });
        if (userError) return json({ error: "server_error" }, 500);
        users.push(...data.users);
        if (data.users.length < 1000) break;
      }
      const rows = (subscriptions ?? []).map((sub) => {
        const profile = (profiles ?? []).find((p) => p.shop_id === sub.shop_id);
        const accounts = users.filter((u) =>
          u.id === sub.owner_user_id || u.app_metadata?.shop_id === sub.shop_id
        ).map((u) => ({
          id: u.id,
          user_id: u.id,
          email: u.email,
          role: u.app_metadata?.role,
          banned_until: u.banned_until,
          banned: !!u.banned_until && Date.parse(u.banned_until) > Date.now(),
        }));
        const bound = (devices ?? []).filter((d) => d.shop_id === sub.shop_id);
        return {
          ...sub,
          shop_name: profile?.name || sub.shop_name || sub.shop_id,
          phone: profile?.phone,
          address: profile?.address,
          status: subscriptionStatus(sub),
          email: accounts.find((a) => a.role === "owner")?.email,
          accounts,
          devices: bound,
          device_ids: bound.map((d) => d.device_id),
          device_count: bound.length,
        };
      });
      if (body.action === "list_shops") return json({ rows });
      const shop = rows.find((r) =>
        body.shop_id
          ? r.shop_id === body.shop_id
          : body.email
          ? r.accounts.some((a: { role: string; email?: string }) =>
            a.role === "owner" &&
            a.email?.toLowerCase() === body.email?.toLowerCase()
          )
          : r.device_ids.includes(body.device_id)
      );
      return shop ? json({ shop }) : json({ error: "not_found" }, 404);
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
        if (
          msg.toLowerCase().includes("not found") ||
          msg.toLowerCase().includes("unable to find")
        ) {
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

      const { data: owned, error: ownerError } = await admin.from(
        "shop_subscriptions",
      )
        .select("shop_id").eq("owner_user_id", userId).limit(1);
      if (ownerError) return json({ error: "server_error" }, 500);
      if (owned?.length) return json({ error: "last_owner" }, 400);

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
      const checked = checkMonths(body.months);
      if ("error" in checked) return json({ error: checked.error }, 400);
      if (!body.shop_id || !body.id) {
        return json({ error: "shop_and_operation_id_required" }, 400);
      }
      const { data, error } = await admin.rpc("renew_shop_subscription", {
        p_shop_id: body.shop_id,
        p_months: checked.months,
        p_payment_id: `admin:${body.id}`,
      });
      if (error) {
        return json({ error: "server_error", detail: error.message }, 500);
      }
      return json({ ...data, ok: true, rows: 1 });
    }
    case "reset_device": {
      if (!body.shop_id || !body.device_id) {
        return json({ error: "bad_request" }, 400);
      }
      const { data: subscription } = await admin.from("shop_subscriptions")
        .select("owner_user_id").eq("shop_id", body.shop_id).maybeSingle();
      if (!subscription?.owner_user_id) {
        return json({ error: "not_found" }, 404);
      }
      const { error } = await admin.rpc("release_shop_device", {
        p_user_id: subscription.owner_user_id,
        p_shop_id: body.shop_id,
        p_device_id: body.device_id,
      });
      return error
        ? json({ error: "server_error" }, 500)
        : json({ ok: true, rows: 1 });
    }
    case "list_requests": {
      const { data, error } = await admin.from("license_requests")
        .select(
          "id, shop_id, shop_name, owner_user_id, plan, months, amount, method, ref_no, phone, payment_proof_path, payment_status, status, created_at, invoice_no, fulfilled_expires_at",
        )
        .order("created_at", { ascending: false }).limit(500);
      return error
        ? json({ error: "server_error" }, 500)
        : json({ rows: data });
    }
    case "fulfill_request": {
      if (!body.request_id) return json({ error: "bad_request" }, 400);
      const { data, error } = await admin.rpc("fulfill_account_payment", {
        p_request_id: body.request_id,
      });
      if (error) {
        return json(
          { error: "payment_not_fulfilled", detail: error.message },
          409,
        );
      }
      return json({ ...data, request_marked_fulfilled: true });
    }

    case "reject_request": {
      if (!body.request_id) return json({ error: "bad_request" }, 400);
      const { data, error } = await admin.rpc("reject_account_payment", {
        p_request_id: body.request_id,
        p_reason: body.reason ?? "",
      });
      return error ? json({ error: "request_not_pending" }, 409) : json(data);
    }

    case "list_events": {
      const { data, error } = await admin.from("shop_subscription_payments")
        .select("payment_id, shop_id, months, expires_at, created_at")
        .order("created_at", { ascending: false }).limit(500);
      if (error) return json({ error: "server_error" }, 500);
      return json({
        rows: (data ?? []).map((row) => ({
          ...row,
          shop_name: row.shop_id,
          action: "extend",
        })),
      });
    }

    case "get_config": {
      const { data, error } = await admin.from("app_config").select(
        "key, value",
      ).in("key", [...PUBLIC_CONFIG_KEYS]);
      if (error) return json({ error: "server_error" }, 500);
      return json({ rows: data });
    }

    case "set_config": {
      const entries = Object.entries(body.config ?? {});
      if (entries.length === 0) return json({ error: "bad_request" }, 400);
      // Allowlisted because `app_config` is world-readable — its RLS policy
      // is `for select to anon, authenticated using (true)`, deliberately, so
      // an unregistered shop can see where to send payment before it can log
      // in. That makes this endpoint a publish button. Without a list, a key
      // typed or pasted into the admin's config editor under the reasonable
      // assumption that "admin settings are private" would be readable by
      // anyone on the internet, and a mistyped key would silently create a
      // dead row instead of failing.
      const unknown = entries
        .map(([k]) => k)
        .filter((k) => !PUBLIC_CONFIG_KEYS.has(k));
      if (unknown.length > 0) {
        return json(
          { error: "unknown_config_key", detail: unknown.join(", ") },
          400,
        );
      }
      if (
        entries.some(([key, value]) =>
          typeof value !== "string" ||
          (key.startsWith("pay.lemonsqueezy.variant_") && value.trim() !== "" &&
            (!/^[1-9]\d*$/.test(value.trim()) ||
              !Number.isSafeInteger(Number(value))))
        )
      ) return json({ error: "invalid_config_value" }, 400);
      const rows = entries.map(([key, value]) => ({
        key,
        value: value.trim(),
        updated_at: new Date().toISOString(),
      }));
      const { error } = await admin.from("app_config").upsert(rows);
      if (error) {
        return json({ error: "server_error", detail: error.message }, 500);
      }
      return json({ ok: true });
    }

    case "set_shop_archived": {
      if (!body.shop_id) return json({ error: "bad_request" }, 400);
      const { data, error } = await admin.rpc("archive_shop_subscription", {
        p_shop_id: body.shop_id,
        p_archived: body.archived === true,
      });
      if (error) {
        return json({
          error: error.message.includes("shop_is_paid")
            ? "shop_is_paid"
            : "server_error",
        }, 409);
      }
      return json(data);
    }

    default:
      return json({ error: "unknown_action" }, 400);
  }
});

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
