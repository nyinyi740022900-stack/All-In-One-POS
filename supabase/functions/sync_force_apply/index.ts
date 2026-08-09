// Edge Function: sync_force_apply
//
// Authenticated shop-scoped heal for outbox rows that PostgREST+RLS keeps
// rejecting. The client never asks the owner to Discard or call Support —
// after N failures it sends the live row here; we verify JWT shop_id matches
// the payload, allowlist the table, then upsert/soft-delete with the service
// role.
//
// POST body:
//   { table, op: 'upsert'|'delete', id, row?, on_conflict? }
//
// Response:
//   { ok: true, status: 'applied'|'already_there'|'rejected_invalid'|'transient',
//     detail?: string }
//
// Deploy: supabase functions deploy sync_force_apply --project-ref gnikispsurwrmkspuisj

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ALLOWED_TABLES = new Set([
  "categories",
  "staff_members",
  "customers",
  "products",
  "stock_levels",
  "stock_movements",
  "sales",
  "sale_items",
  "license_payments",
  "credit_payments",
  "supplier_payments",
  "orders",
  "order_items",
  "payments",
  "expenses",
  "cash_sessions",
  "device_labels",
  "recurring_expenses",
  "suppliers",
  "payment_accounts",
  "equity_entries",
  "purchase_orders",
  "purchase_order_items",
]);

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ ok: false, status: "transient", detail: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  const asUser = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await asUser.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ ok: false, status: "transient", detail: "not_authenticated" }, 401);
  }

  const claimShopId = userData.user.app_metadata?.shop_id as string | undefined;
  if (!claimShopId || typeof claimShopId !== "string") {
    return json({ ok: false, status: "rejected_invalid", detail: "no_shop_claim" }, 403);
  }

  let body: {
    table?: string;
    op?: string;
    id?: string;
    row?: Record<string, unknown>;
    on_conflict?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, status: "rejected_invalid", detail: "bad_json" }, 400);
  }

  const table = body.table ?? "";
  const op = body.op ?? "";
  const id = body.id ?? "";
  if (!ALLOWED_TABLES.has(table)) {
    return json({ ok: false, status: "rejected_invalid", detail: "table_not_allowed" }, 400);
  }
  if (op !== "upsert" && op !== "delete") {
    return json({ ok: false, status: "rejected_invalid", detail: "bad_op" }, 400);
  }
  if (!id || typeof id !== "string") {
    return json({ ok: false, status: "rejected_invalid", detail: "bad_id" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);

  try {
    if (op === "delete") {
      const updatedAt = new Date().toISOString();
      const { error } = await admin
        .from(table)
        .update({ is_deleted: true, updated_at: updatedAt })
        .eq("id", id)
        .eq("shop_id", claimShopId);
      if (error) {
        // Already gone is fine.
        if (isMissing(error)) {
          return json({ ok: true, status: "already_there" });
        }
        return json({
          ok: false,
          status: "transient",
          detail: error.message,
        }, 200);
      }
      return json({ ok: true, status: "applied" });
    }

    const row = body.row;
    if (!row || typeof row !== "object") {
      return json({ ok: false, status: "rejected_invalid", detail: "missing_row" }, 400);
    }
    if (row["id"] !== id) {
      return json({ ok: false, status: "rejected_invalid", detail: "id_mismatch" }, 400);
    }
    if (row["shop_id"] !== claimShopId) {
      return json({ ok: false, status: "rejected_invalid", detail: "shop_mismatch" }, 403);
    }
    if (typeof row["updated_at"] !== "string") {
      return json({ ok: false, status: "rejected_invalid", detail: "bad_updated_at" }, 400);
    }

    // Already present?
    const { data: existing, error: selErr } = await admin
      .from(table)
      .select("id")
      .eq("shop_id", claimShopId)
      .eq("id", id)
      .maybeSingle();
    if (selErr && !isMissing(selErr)) {
      return json({ ok: false, status: "transient", detail: selErr.message }, 200);
    }
    if (existing) {
      // Still upsert to refresh LWW fields when client is newer — service role.
      const { error: upErr } = await admin.from(table).upsert(row, {
        onConflict: body.on_conflict ?? "id",
      });
      if (upErr) {
        return json({ ok: false, status: "transient", detail: upErr.message }, 200);
      }
      return json({ ok: true, status: "already_there" });
    }

    const { error: insErr } = await admin.from(table).upsert(row, {
      onConflict: body.on_conflict ?? "id",
    });
    if (insErr) {
      // FK / check constraint → rejected_invalid so client can decide.
      if (isConstraint(insErr)) {
        return json({
          ok: false,
          status: "rejected_invalid",
          detail: insErr.message,
        }, 200);
      }
      return json({ ok: false, status: "transient", detail: insErr.message }, 200);
    }
    return json({ ok: true, status: "applied" });
  } catch (e) {
    return json({
      ok: false,
      status: "transient",
      detail: e instanceof Error ? e.message : "unknown",
    }, 200);
  }
});

function isMissing(error: { code?: string; message?: string }): boolean {
  const code = (error.code ?? "").toString();
  const msg = (error.message ?? "").toLowerCase();
  return code === "PGRST116" || msg.includes("0 rows") || msg.includes("not found");
}

function isConstraint(error: { code?: string; message?: string }): boolean {
  const code = (error.code ?? "").toString();
  const msg = (error.message ?? "").toLowerCase();
  return (
    code === "23503" ||
    code === "23502" ||
    code === "23514" ||
    msg.includes("foreign key") ||
    msg.includes("violates check") ||
    msg.includes("not-null")
  );
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
