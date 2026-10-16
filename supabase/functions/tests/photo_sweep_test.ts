import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type SweepClient, sweepOrphanPhotos } from "../_shared/photo_sweep.ts";

/// A bucket the fake database lists from and the fake Storage API deletes
/// from — so a pass after a removal sees the removal, as the real one does.
function fakeBucket(
  names: string[],
  opts: { failRemove?: boolean; rpcError?: boolean; stuck?: boolean } = {},
) {
  const files = new Set(names);
  const removed: string[][] = [];
  let calls = 0;
  const client: SweepClient = {
    rpc(_fn, args) {
      calls++;
      if (opts.rpcError) return Promise.resolve({ data: null, error: "boom" });
      const data = [...files].slice(0, args.p_limit).map((name) => ({
        name,
        bytes: 10,
        created_at: "2026-01-01T00:00:00Z",
      }));
      return Promise.resolve({ data, error: null });
    },
    storage: {
      from: () => ({
        remove(paths: string[]) {
          removed.push(paths);
          if (opts.failRemove) return Promise.resolve({ error: "denied" });
          if (!opts.stuck) for (const p of paths) files.delete(p);
          return Promise.resolve({ error: null });
        },
      }),
    },
  };
  return { client, files, removed, calls: () => calls };
}

Deno.test("a dry run lists what a real run would remove and removes nothing", async () => {
  const b = fakeBucket(["s/p-1.jpg", "s/p-2.jpg"]);
  const s = await sweepOrphanPhotos(b.client, { dryRun: true });
  assertEquals(s, {
    ok: true,
    dry_run: true,
    files: 2,
    bytes: 20,
    names: ["s/p-1.jpg", "s/p-2.jpg"],
  });
  assertEquals(b.removed, []);
  assertEquals(b.files.size, 2);
});

Deno.test("a real run removes every orphan in chunks of at most 100", async () => {
  const names = Array.from({ length: 250 }, (_, i) => `s/p-${i}.jpg`);
  const b = fakeBucket(names);
  const s = await sweepOrphanPhotos(b.client, { dryRun: false });
  assertEquals(s.ok, true);
  assertEquals(s.files, 250);
  assertEquals(s.bytes, 2500);
  assertEquals(b.files.size, 0);
  assertEquals(b.removed.map((c) => c.length), [100, 100, 50]);
});

Deno.test("more than a page is drained across passes", async () => {
  const names = Array.from({ length: 1500 }, (_, i) => `s/p-${i}.jpg`);
  const b = fakeBucket(names);
  const s = await sweepOrphanPhotos(b.client, { dryRun: false });
  assertEquals(s.files, 1500);
  assertEquals(b.files.size, 0);
});

Deno.test("a removal that silently keeps files cannot loop for ever", async () => {
  const names = Array.from({ length: 1000 }, (_, i) => `s/p-${i}.jpg`);
  const b = fakeBucket(names, { stuck: true });
  const s = await sweepOrphanPhotos(b.client, { dryRun: false });
  assertEquals(s.ok, true);
  assertEquals(b.calls(), 20);
});

Deno.test("a failed removal stops the run and reports it", async () => {
  const b = fakeBucket(["s/p-1.jpg"], { failRemove: true });
  const s = await sweepOrphanPhotos(b.client, { dryRun: false });
  assertEquals(s.ok, false);
  assertEquals(s.error, "remove_failed");
  assertEquals(s.files, 0);
});

Deno.test("a database error or a suspicious name deletes nothing", async () => {
  const err = fakeBucket(["s/p-1.jpg"], { rpcError: true });
  assertEquals((await sweepOrphanPhotos(err.client, { dryRun: false })).ok, false);
  assertEquals(err.removed, []);
  for (const bad of ["", "s/../other/p.jpg"]) {
    const b = fakeBucket(["s/ok.jpg", bad]);
    const s = await sweepOrphanPhotos(b.client, { dryRun: false });
    assertEquals(s.ok, false, `name ${JSON.stringify(bad)}`);
    assertEquals(b.removed, [], "the whole page is refused, not just the bad name");
  }
});
