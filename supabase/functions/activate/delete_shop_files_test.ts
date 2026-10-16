import { deleteShopFiles } from "./index.ts";

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

/// In-memory stand-in for `admin.storage`: object keys per bucket, with a
/// list() that only sees the first level under the prefix, like Supabase.
function fakeStorage(seed: Record<string, string[]>) {
  const buckets: Record<string, Set<string>> = {};
  for (const [b, keys] of Object.entries(seed)) buckets[b] = new Set(keys);
  let failRemove = false;
  const admin = {
    rpc: (_name: string, args: { p_owner_user_id: string }) =>
      Promise.resolve({
        data: [...(buckets["product-images"] ?? [])]
          .filter((k) =>
            !k.includes("/") && k.startsWith(`${args.p_owner_user_id}-`)
          )
          .slice(0, 1000).map((name) => ({ name })),
        error: null,
      }),
    storage: {
      from: (bucket: string) => ({
        list: (prefix: string, opts: { limit: number }) => {
          const paths = [...(buckets[bucket] ?? [])]
            .filter((k) => k.startsWith(`${prefix}/`))
            .map((k) => k.slice(prefix.length + 1));
          const names = [...new Set(paths.map((k) => k.split("/")[0]))]
            .slice(0, opts.limit).map((name) => ({
              name,
              id: paths.some((p) => p === name) ? name : null,
            }));
          return Promise.resolve({ data: names, error: null });
        },
        remove: (keys: string[]) => {
          if (failRemove) {
            return Promise.resolve({ error: { message: "unavailable" } });
          }
          for (const k of keys) buckets[bucket]?.delete(k);
          return Promise.resolve({ error: null });
        },
      }),
    },
  };
  return {
    admin,
    buckets,
    setFailRemove: (v: boolean) => (failRemove = v),
  };
}

Deno.test("account deletion removes the deleted shops' files in both buckets", async () => {
  const s = fakeStorage({
    "product-images": ["shop-a/p-1.jpg", "shop-a/logo-2.png", "shop-b/p-9.jpg"],
    "payment-proofs": [
      "shop-a/proof-1.jpg",
      "shop-b/proof-2.jpg",
      "_admin/owner-a/proof-3.jpg",
    ],
  });
  assert(await deleteShopFiles(s.admin, new Set(["shop-a"])), "should succeed");
  assert(
    ![...s.buckets["product-images"]].some((k) => k.startsWith("shop-a/")),
    "shop-a product photos and logo must be gone",
  );
  assert(
    ![...s.buckets["payment-proofs"]].some((k) => k.startsWith("shop-a/")),
    "shop-a customers' transfer screenshots must be gone",
  );
  assert(
    s.buckets["product-images"].has("shop-b/p-9.jpg") &&
      s.buckets["payment-proofs"].has("shop-b/proof-2.jpg"),
    "another shop's files must be untouched",
  );
  assert(
    s.buckets["payment-proofs"].has("_admin/owner-a/proof-3.jpg"),
    "the owner's own Premium payment proof is a billing record and stays",
  );
});

Deno.test("deletion cleans owned legacy flat files before scoped folders, retaining other owners", async () => {
  const s = fakeStorage({
    "product-images": ["owner-a-old.jpg", "owner-b-old.jpg", "shop-a/new.jpg"],
    "payment-proofs": [],
  });
  assert(
    await deleteShopFiles(s.admin, new Set(["shop-a"]), "owner-a"),
    "cleanup succeeds",
  );
  assert(
    !s.buckets["product-images"].has("owner-a-old.jpg"),
    "old flat photo must be deleted",
  );
  assert(
    s.buckets["product-images"].has("owner-b-old.jpg"),
    "other owner's old file stays",
  );
});

Deno.test("legacy cleanup re-lists all batches and fails closed on ownership lookup errors", async () => {
  const s = fakeStorage({
    "product-images": Array.from(
      { length: 2500 },
      (_, i) => `owner-a-${i}.jpg`,
    ),
  });
  assert(
    await deleteShopFiles(s.admin, new Set(["shop-a"]), "owner-a"),
    "cleanup succeeds",
  );
  assert(s.buckets["product-images"].size === 0, "all legacy pages removed");
  s.admin.rpc = () =>
    Promise.resolve({ data: [], error: { message: "unavailable" } }) as never;
  assert(
    !await deleteShopFiles(s.admin, new Set(["shop-a"]), "owner-a"),
    "lookup errors must not report deletion complete",
  );
});

Deno.test("legacy removal failure leaves Auth cleanup pending and retries safely", async () => {
  const s = fakeStorage({
    "product-images": ["owner-a-old.jpg", "owner-b-old.jpg"],
  });
  s.setFailRemove(true);
  assert(
    !await deleteShopFiles(s.admin, new Set(["shop-a"]), "owner-a"),
    "failure must stop account deletion",
  );
  assert(
    s.buckets["product-images"].has("owner-a-old.jpg"),
    "failed removal retains the retry target",
  );
  s.setFailRemove(false);
  assert(
    await deleteShopFiles(s.admin, new Set(["shop-a"]), "owner-a"),
    "retry succeeds",
  );
  assert(
    s.buckets["product-images"].has("owner-b-old.jpg"),
    "other owner stays untouched",
  );
});

Deno.test("account deletion pages through a folder with more than one listing", async () => {
  const many = Array.from({ length: 2500 }, (_, i) => `shop-a/p-${i}.jpg`);
  const s = fakeStorage({ "product-images": many, "payment-proofs": [] });
  assert(await deleteShopFiles(s.admin, new Set(["shop-a"])), "should succeed");
  assert(
    s.buckets["product-images"].size === 0,
    `all 2,500 files must go, ${s.buckets["product-images"].size} left`,
  );
});

Deno.test("account deletion removes nested folders without touching other shops", async () => {
  const s = fakeStorage({
    "product-images": ["shop-a/old/photo.jpg"],
    "payment-proofs": [
      "shop-a/orders/old/proof.jpg",
      "shop-b/orders/proof.jpg",
    ],
  });
  assert(
    await deleteShopFiles(s.admin, new Set(["shop-a"])),
    "cleanup succeeds",
  );
  assert(
    s.buckets["product-images"].size === 0,
    "nested product photo removed",
  );
  assert(
    s.buckets["payment-proofs"].size === 1 &&
      s.buckets["payment-proofs"].has("shop-b/orders/proof.jpg"),
    "only other shop remains",
  );
});

Deno.test("a failed file removal fails deletion so it is retried, not reported done", async () => {
  const s = fakeStorage({
    "product-images": ["shop-a/p-1.jpg"],
    "payment-proofs": ["shop-a/proof-1.jpg"],
  });
  s.setFailRemove(true);
  assert(
    !await deleteShopFiles(s.admin, new Set(["shop-a"])),
    "a storage failure must not report success (the Auth owner would be deleted)",
  );
  s.setFailRemove(false);
  assert(await deleteShopFiles(s.admin, new Set(["shop-a"])), "retry succeeds");
  assert(
    s.buckets["product-images"].size === 0 &&
      s.buckets["payment-proofs"].size === 0,
    "retry finishes the cleanup",
  );
});
