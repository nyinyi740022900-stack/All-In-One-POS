import { handleForceApply } from "./index.ts";
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
Deno.test("force apply cannot mutate a Free, lapsed, revoked or released account", async () => {
  for (
    const gate of [{ data: "", error: null }, {
      data: null,
      error: { message: "network" },
    }]
  ) {
    let mutations = 0;
    const asUser = {
      auth: {
        getUser: () =>
          Promise.resolve({
            data: { user: { app_metadata: { shop_id: "a" } } },
            error: null,
          }),
      },
      rpc: () => Promise.resolve(gate),
      from: () => {
        mutations++;
        throw new Error("must not mutate");
      },
    };
    const response = await handleForceApply(
      new Request("https://local.test", {
        method: "POST",
        body: JSON.stringify({ table: "sales", op: "delete", id: "sale" }),
      }),
      asUser,
    );
    const body = await response.json();
    assert(mutations === 0, "entitlement gate must run before any data query");
    assert(
      body.status === "transient",
      "paused sync must preserve queued writes",
    );
  }
});
