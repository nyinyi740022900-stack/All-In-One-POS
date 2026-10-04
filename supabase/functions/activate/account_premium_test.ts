import { signEntitlement, withEntitlement } from "../_shared/entitlement.ts";

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
const input = {
  shopId: "shop-a",
  userId: "user-a",
  deviceId: "device-a",
  revision: 4,
  plan: "monthly",
  expiresAt: "2030-01-01T00:00:00Z",
};
Deno.test("Premium receipt signs version 2 with all account/device bindings", async () => {
  Deno.env.set("ENTITLEMENT_SIGNING_KEY_HEX", "11".repeat(32));
  const token = await signEntitlement(input);
  assert(token, "must issue proof");
  const payload = JSON.parse(
    atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")),
  );
  assert(payload.v === 2, "must sign version 2");
  assert(
    payload.user_id === input.userId && payload.device_id === input.deviceId &&
      payload.revision === 4,
    "must bind user/device/revision",
  );
});
Deno.test("unbound, invalid, Free and unknown-plan receipts cannot be issued", async () => {
  for (
    const patch of [
      { userId: "" },
      { deviceId: "" },
      { revision: -1 },
      { plan: "free" },
      { plan: "unknown" },
      { expiresAt: "bad" },
    ]
  ) {
    assert(
      await signEntitlement({ ...input, ...patch }) === undefined,
      `must reject ${JSON.stringify(patch)}`,
    );
  }
  const free = await withEntitlement({
    shop_id: "shop-a",
    plan: "free",
    expires_at: "1970-01-01T00:00:00Z",
  });
  assert(!free.entitlement, "Free needs no proof");
});

import { retiredAccountAction } from "../_shared/account_premium.ts";
Deno.test("key activation and old device/tier paths are explicitly retired", () => {
  for (
    const action of [
      "activate",
      "link_branch",
      "request_device_slot",
      "set_tier",
    ]
  ) {
    assert(
      retiredAccountAction(action) === "retired_path",
      `must retire ${action}`,
    );
  }
  assert(
    retiredAccountAction("refresh_account_license") === null,
    "account refresh remains reachable",
  );
});

import { handleAccountAction, handleRequest } from "./index.ts";
import { trustedShopId } from "../_shared/account_premium.ts";
import * as ed from "https://esm.sh/@noble/ed25519@2.1.0";
Deno.test("receipt signature verifies exact bound payload and rejects tampering", async () => {
  const token = await signEntitlement(input);
  assert(token, "receipt missing");
  const [prefix, encoded, encodedSignature] = token.split(".");
  const signature = Uint8Array.from(
    atob(encodedSignature.replace(/-/g, "+").replace(/_/g, "/")),
    (c) => c.charCodeAt(0),
  );
  const publicKey = await ed.getPublicKeyAsync(new Uint8Array(32).fill(0x11));
  assert(
    await ed.verifyAsync(
      signature,
      new TextEncoder().encode(`${prefix}.${encoded}`),
      publicKey,
    ),
    "signature must verify",
  );
  assert(
    !await ed.verifyAsync(
      signature,
      new TextEncoder().encode(`${prefix}.${encoded}x`),
      publicKey,
    ),
    "edited proof must fail",
  );
});
Deno.test("actual HTTP handler retires all key paths including implicit default", async () => {
  for (
    const action of [
      undefined,
      "activate",
      "link_branch",
      "request_device_slot",
      "set_tier",
    ]
  ) {
    const response = await handleRequest(
      new Request("https://local.test/activate", {
        method: "POST",
        body: JSON.stringify({
          action,
          key: "old-key",
          device_id: "public-id",
        }),
      }),
    );
    assert(
      (await response.json()).error === "retired_path",
      "must stop before any key lookup or auth mutation",
    );
  }
});
Deno.test("anonymous trial and editable user metadata never prove ownership", async () => {
  assert(
    trustedShopId({ id: "u", ...{ user_metadata: { shop_id: "victim" } } }) ===
      null,
    "must ignore user-editable metadata",
  );
  const response = await handleAccountAction(
    {},
    { id: "anonymous", is_anonymous: true },
    "start_trial",
    { device_id: "d" },
  );
  assert(
    (await response.json()).error === "account_required",
    "trial must require a real account",
  );
});
Deno.test("signup invokes only Free authority and returns no Premium proof", async () => {
  const calls: string[] = [];
  const admin = {
    rpc(name: string, params: Record<string, string>) {
      calls.push(name);
      return Promise.resolve({
        data: {
          shop_id: params.p_shop_id,
          plan: "free",
          expires_at: "1970-01-01T00:00:00Z",
          activated_at: "2026-10-03T00:00:00Z",
          revision: 1,
        },
        error: null,
      });
    },
    auth: {
      admin: {
        createUser: () =>
          Promise.resolve({
            data: { user: { id: "new-owner", email: "owner@example.com" } },
            error: null,
          }),
        updateUserById: () => Promise.resolve({ error: null }),
      },
    },
  };
  const response = await handleAccountAction(
    admin,
    { id: "anonymous", is_anonymous: true },
    "signup_shop",
    {
      email: "owner@example.com",
      password: "test-only-password",
      device_id: "d",
    },
  );
  const body = await response.json();
  assert(
    body.ok && body.plan === "free" && !body.entitlement,
    "signup must remain Free",
  );
  assert(
    body.user_id === "new-owner" && body.device_id === "d",
    "identity must survive Free signup",
  );
  assert(
    calls.length === 1 && calls[0] === "create_account_shop",
    "signup cannot mint a trial/key",
  );
});

import { deleteExistingShopRows } from "./index.ts";
Deno.test("account deletion stops on a failed table and can retry existing cleanup", async () => {
  const pending = new Set(["sale_items", "payments", "shop_profiles"]);
  let unavailable = true;
  const admin = {
    from: (table: string) => ({
      delete: () => ({
        eq: () => {
          if (table === "payments" && unavailable) {
            return Promise.resolve({
              error: { message: "unavailable" },
            });
          }
          pending.delete(table);
          return Promise.resolve({ error: null });
        },
      }),
    }),
  };
  assert(
    !await deleteExistingShopRows(admin, new Set(["a"])),
    "failed cleanup cannot report success or remove Auth owner",
  );
  assert(
    pending.has("payments") && pending.has("shop_profiles"),
    "must stop after the first failed table",
  );
  unavailable = false;
  assert(
    await deleteExistingShopRows(admin, new Set(["a"])),
    "retry must finish remaining cleanup",
  );
  assert(
    pending.size === 0,
    "shop profile must be removed with existing business data",
  );
});

Deno.test("signup preserves spaces in the owner's password", async () => {
  let received = "";
  const admin = {
    auth: {
      admin: {
        createUser: (params: { password: string }) => {
          received = params.password;
          return Promise.resolve({ error: { message: "already registered" } });
        },
      },
    },
  };
  await handleAccountAction(
    admin,
    { id: "anonymous", is_anonymous: true },
    "signup_shop",
    {
      email: "owner@example.com",
      password: " password with spaces ",
      device_id: "d",
    },
  );
  assert(
    received === " password with spaces ",
    "Auth must receive the exact password",
  );
});
