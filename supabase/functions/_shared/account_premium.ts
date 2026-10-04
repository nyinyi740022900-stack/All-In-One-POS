import { withEntitlement } from "./entitlement.ts";

// Database calls use a service-role client; identity always comes from getUser.
// deno-lint-ignore no-explicit-any
export type AccountAdmin = any;
export interface AccountUser {
  id: string;
  email?: string;
  is_anonymous?: boolean;
  app_metadata?: Record<string, unknown>;
}
export function retiredAccountAction(action: string): string | null {
  return ["activate", "link_branch", "request_device_slot", "set_tier"]
      .includes(action)
    ? "retired_path"
    : null;
}
export function trustedShopId(user: AccountUser): string | null {
  const shop = user.app_metadata?.shop_id;
  return typeof shop === "string" && shop.trim() ? shop : null;
}
export function realAccount(user: AccountUser): boolean {
  return user.is_anonymous !== true && !!user.email;
}
export function hasPremium(subscription: Record<string, unknown>): boolean {
  const status = subscriptionStatus(subscription);
  return status === "active" || status === "grace";
}
export function subscriptionStatus(
  subscription: Record<string, unknown>,
  now = Date.now(),
): "free" | "active" | "grace" | "expired" {
  if (subscription.is_archived) return "expired";
  if (subscription.plan === "free") return "free";
  if (!["monthly", "yearly", "trial"].includes(String(subscription.plan))) {
    return "expired";
  }
  const expiry = Date.parse(String(subscription.expires_at));
  if (expiry >= now) return "active";
  return expiry + 14 * 86400000 >= now ? "grace" : "expired";
}
export async function accountRole(
  admin: AccountAdmin,
  userId: string,
  shopId: string,
): Promise<string | null> {
  const { data, error } = await admin.rpc("account_shop_role", {
    p_user_id: userId,
    p_shop_id: shopId,
  });
  if (error) throw new Error("server_error");
  return data;
}
export async function resolveAccountShop(
  admin: AccountAdmin,
  user: AccountUser,
  selected?: string,
): Promise<string | null> {
  // An explicit selection is checked, never silently replaced with a different shop.
  const shop = selected || trustedShopId(user);
  if (shop) return await accountRole(admin, user.id, shop) ? shop : null;
  const { data, error } = await admin.from("org_branches").select("shop_id")
    .eq("owner_user_id", user.id).order("last_active_at", { ascending: false });
  if (error) throw new Error("server_error");
  for (const branch of data ?? []) {
    if (await accountRole(admin, user.id, branch.shop_id) === "owner") {
      return branch.shop_id;
    }
  }
  return null;
}
const businessErrors = new Set([
  "not_authenticated",
  "membership_revoked",
  "shop_archived",
  "device_released",
  "device_limit_reached",
  "ownership_verification_required",
  "account_already_linked",
  "free_device_replacement_required",
  "trial_already_used",
  "already_premium",
  "bad_request",
  "forbidden",
  "not_found",
]);
export function accountError(error: { message?: string } | null): string {
  const message = error?.message ?? "";
  return businessErrors.has(message) ? message : "server_error";
}
export async function subscriptionReply(
  subscription: Record<string, unknown>,
  userId: string,
  deviceId: string,
): Promise<Record<string, unknown>> {
  return await withEntitlement({
    ok: true,
    shop_id: subscription.shop_id,
    plan: subscription.plan,
    expires_at: subscription.expires_at,
    activated_at: subscription.activated_at,
    revision: Number(subscription.revision),
    user_id: userId,
    device_id: deviceId,
    key: "SIGNUP",
    tier: "online",
    realtime_enabled: hasPremium(subscription),
  });
}
