import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { subscriptionStatus } from "../_shared/account_premium.ts";
const now = Date.parse("2026-10-04T00:00:00Z");
Deno.test("subscription status distinguishes active, grace and expiry at exact boundaries", () => {
  const sub = { plan: "monthly", expires_at: new Date(now).toISOString() };
  assertEquals(subscriptionStatus(sub, now), "active");
  assertEquals(subscriptionStatus(sub, now + 1), "grace");
  assertEquals(subscriptionStatus(sub, now + 14 * 86400000), "grace");
  assertEquals(subscriptionStatus(sub, now + 14 * 86400000 + 1), "expired");
});
Deno.test("free, archived and invalid subscriptions are never shown active", () => {
  const sub = { plan: "monthly", expires_at: "2027-01-01T00:00:00Z" };
  assertEquals(subscriptionStatus({ ...sub, plan: "free" }, now), "free");
  assertEquals(
    subscriptionStatus({ ...sub, is_archived: true }, now),
    "expired",
  );
  assertEquals(subscriptionStatus({ ...sub, plan: "unknown" }, now), "expired");
  assertEquals(
    subscriptionStatus({ ...sub, expires_at: "invalid" }, now),
    "expired",
  );
});
