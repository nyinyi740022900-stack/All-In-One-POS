import { handleAccountAction } from "./index.ts";
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
const user = { id: "owner", email: "owner@example.com", app_metadata: {} };
function authority(result: unknown, error: { message: string } | null = null) {
  let metadata: unknown;
  const calls: string[] = [];
  return {
    from: () => ({
      select: () => ({
        eq: () => ({ order: () => Promise.resolve({ data: [], error: null }) }),
      }),
    }),
    calls,
    get metadata() {
      return metadata;
    },
    rpc(name: string) {
      calls.push(name);
      return Promise.resolve({ data: result, error });
    },
    auth: {
      admin: {
        updateUserById(_id: string, patch: unknown) {
          metadata = patch;
          return Promise.resolve({ error: null });
        },
      },
    },
  };
}
for (const role of ["owner", "staff"]) {
  Deno.test(`prepare social restores authoritative ${role} without provisioning`, async () => {
    const admin = authority({
      needs_shop_name: false,
      shop_id: "existing",
      role,
    });
    const body = await (await handleAccountAction(
      admin,
      user,
      "prepare_social_account",
      {},
    )).json();
    assert(
      body.ok && body.shop_id === "existing" && body.needs_shop_name === false,
      "must restore membership",
    );
    assert(
      JSON.stringify(admin.metadata).includes(`"role":"${role}"`),
      "must retain authoritative role",
    );
    assert(
      admin.calls.join() === "resolve_social_account",
      "must not create a shop",
    );
  });
}
Deno.test("prepare new social account requests shop name without assigning owner", async () => {
  const admin = authority({ needs_shop_name: true });
  const body =
    await (await handleAccountAction(admin, user, "prepare_social_account", {}))
      .json();
  assert(
    body.ok && body.needs_shop_name === true,
    "new account must request name",
  );
  assert(!admin.metadata, "unprovisioned user must not gain owner role");
});
Deno.test("repeated social signup uses idempotent authority and no trial or device receipt", async () => {
  const admin = authority({ shop_id: "existing", plan: "free", revision: 1 });
  for (let i = 0; i < 2; i++) {
    const body =
      await (await handleAccountAction(admin, user, "signup_social_shop", {
        shop_name: "Shop",
        device_id: "unbound",
      })).json();
    assert(
      body.ok && body.shop_id === "existing" && body.plan === "free" &&
        !body.entitlement,
      "must reuse Free shop",
    );
  }
  assert(
    admin.calls.join() ===
      "create_social_account_shop,create_social_account_shop",
    "must use serialized first-shop authority",
  );
});
Deno.test("legacy signup cannot promote an authenticated social staff account", async () => {
  const admin = authority(null, { message: "forbidden" });
  const result = await (await handleAccountAction(
    admin,
    { ...user, app_metadata: { role: "staff", shop_id: "staff-shop" } },
    "signup_shop",
    { device_id: "d", shop_name: "Bad" },
  )).json();
  assert(
    result.error === "forbidden" && !admin.metadata,
    "staff must retain role",
  );
  assert(
    admin.calls.join() === "create_social_account_shop",
    "legacy action must use first-shop authority",
  );
});
Deno.test("legacy signup reuses an existing social owner shop without duplicate creation", async () => {
  const admin = authority({ shop_id: "existing", plan: "free", revision: 1 });
  const result = await (await handleAccountAction(admin, user, "signup_shop", {
    device_id: "d",
    shop_name: "Duplicate",
  })).json();
  assert(
    result.ok && result.shop_id === "existing",
    "must reuse existing owner shop",
  );
  assert(
    admin.calls.join() === "create_social_account_shop",
    "must serialize via same authority",
  );
});
