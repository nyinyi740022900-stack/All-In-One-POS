import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

// handleAccountAction is the real handler; only PostgREST/RPC is substituted.
Deno.env.set("SUPABASE_URL", "https://staging.supabase.co");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service");
Deno.env.set("SUPABASE_ANON_KEY", "test-anon");
Deno.env.delete("PLAY_INTEGRITY_SA_JSON");
const originalServe = Deno.serve;
Deno.serve = (() => ({})) as unknown as typeof Deno.serve;
const { handleAccountAction } = await import("./index.ts");
Deno.serve = originalServe;

const owner = {
  id: "user-a",
  email: "owner@example.com",
  app_metadata: { shop_id: "shop-a", role: "owner" },
};

function fakeAdmin(mode: string, insertError: unknown = null) {
  const rpcs: string[] = [];
  const logged: Record<string, unknown>[] = [];
  const admin = {
    rpc(name: string) {
      rpcs.push(name);
      if (name === "account_shop_role") {
        return Promise.resolve({ data: "owner", error: null });
      }
      return Promise.resolve({
        data: {
          shop_id: "shop-a",
          plan: "free",
          expires_at: "1970-01-01T00:00:00Z",
          revision: 1,
        },
        error: null,
      });
    },
    from(table: string) {
      if (table === "app_config") {
        return {
          select: () => ({
            eq: () => ({
              maybeSingle: () =>
                Promise.resolve({ data: { value: mode }, error: null }),
            }),
          }),
        };
      }
      if (table === "integrity_checks") {
        return {
          insert: (row: Record<string, unknown>) => {
            logged.push(row);
            return Promise.resolve({
              error: logged.length === 1 ? insertError : null,
            });
          },
        };
      }
      return {
        update: () => ({ eq: () => ({ eq: () => Promise.resolve({}) }) }),
      };
    },
    auth: { admin: { updateUserById: () => Promise.resolve({ error: null }) } },
  };
  return { admin, rpcs, logged };
}

// An attesting Android build whose token can't be tied to this request.
const badAndroid = {
  shop_id: "shop-a",
  device_id: "dev-1",
  platform: "android",
  app_build: 9,
  integrity_token: "token-without-nonce",
};

Deno.test("enforce: a failing attestation stops the trial before it is claimed", async () => {
  const { admin, rpcs, logged } = fakeAdmin("enforce");
  const res = await handleAccountAction(admin, owner, "start_trial", badAndroid);
  assertEquals((await res.json()).error, "integrity_failed");
  assertEquals(rpcs.includes("start_account_trial"), false);
  assertEquals(logged[0].verdict, "fail");
  assertEquals(logged[0].mode, "enforce");
});

Deno.test("monitor: the same call goes through and is recorded", async () => {
  const { admin, rpcs, logged } = fakeAdmin("monitor");
  const res = await handleAccountAction(admin, owner, "start_trial", badAndroid);
  assertEquals((await res.json()).ok, true);
  assertEquals(rpcs.includes("start_account_trial"), true);
  assertEquals([logged[0].verdict, logged[0].mode], ["fail", "monitor"]);
});

Deno.test("enforce: a phone without Play services is let through, logged", async () => {
  const { admin, rpcs, logged } = fakeAdmin("enforce");
  const res = await handleAccountAction(admin, owner, "refresh_account_license", {
    shop_id: "shop-a",
    device_id: "dev-1",
    platform: "android",
    app_build: 9,
    integrity_nonce: "n-1",
    integrity_error: "PLAY_SERVICES_NOT_FOUND",
  });
  assertEquals((await res.json()).ok, true);
  assertEquals(rpcs.includes("register_shop_device"), true);
  assertEquals(logged[0].verdict, "unavailable");
});

Deno.test("enforce: a reused nonce is a replay and is refused", async () => {
  const { admin, rpcs, logged } = fakeAdmin("enforce", { code: "23505" });
  const res = await handleAccountAction(admin, owner, "refresh_account_license", {
    shop_id: "shop-a",
    device_id: "dev-1",
    platform: "android",
    app_build: 9,
    integrity_nonce: "seen-before",
    integrity_error: "PLAY_SERVICES_NOT_FOUND",
  });
  assertEquals((await res.json()).error, "integrity_failed");
  assertEquals(rpcs.includes("register_shop_device"), false);
  assertEquals(logged[1].reason, "replay");
});

Deno.test("iOS, web and builds before attestation are never blocked", async () => {
  for (
    const body of [
      { platform: "ios" },
      { platform: "web" },
      { platform: "android", app_build: 8 },
    ]
  ) {
    const { admin } = fakeAdmin("enforce");
    const res = await handleAccountAction(admin, owner, "refresh_account_license", {
      shop_id: "shop-a",
      device_id: "dev-1",
      ...body,
    });
    assertEquals((await res.json()).ok, true, JSON.stringify(body));
  }
});
