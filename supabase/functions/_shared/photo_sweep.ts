// Removes product photos nothing points at any more (migration 0104's
// `orphan_product_images` decides which; this only carries it out).
//
// Shared by the cron-only `storage-sweep` function, which deletes, and the
// admin console's dry run, which only lists — so what the admin was shown is
// exactly what the schedule would remove.

export interface Orphan {
  name: string;
  bytes: number;
  created_at: string;
}

export interface SweepSummary {
  ok: boolean;
  error?: string;
  dry_run: boolean;
  files: number;
  bytes: number;
  names?: string[];
}

/// The slice of a Supabase client this needs, so a test can hand in a fake.
export interface SweepClient {
  rpc(
    fn: "orphan_product_images",
    args: { p_min_age: string; p_limit: number },
  ): PromiseLike<{ data: unknown; error: unknown }>;
  storage: {
    from(bucket: "product-images"): {
      remove(paths: string[]): PromiseLike<{ error: unknown }>;
    };
  };
}

export const SWEEP_MIN_AGE = "30 days";
const PAGE = 1000;
const REMOVE_CHUNK = 100;
// Each pass re-asks the database, which only returns files still present. A
// pass that removes nothing would loop for ever, so the count is capped and a
// stuck run just finishes the rest tomorrow.
const MAX_PASSES = 20;

function orphansFrom(data: unknown): Orphan[] | null {
  if (!Array.isArray(data)) return null;
  const out: Orphan[] = [];
  for (const row of data) {
    const name = (row as { name?: unknown })?.name;
    // The bucket holds nothing but `<shop>/<file>` and old root files; a name
    // that is empty or walks upward is not something this should ever touch.
    if (typeof name !== "string" || !name || name.split("/").includes("..")) {
      return null;
    }
    out.push({
      name,
      bytes: Number((row as { bytes?: unknown }).bytes) || 0,
      created_at: String((row as { created_at?: unknown }).created_at ?? ""),
    });
  }
  return out;
}

export async function sweepOrphanPhotos(
  client: SweepClient,
  { dryRun }: { dryRun: boolean },
): Promise<SweepSummary> {
  const summary: SweepSummary = { ok: true, dry_run: dryRun, files: 0, bytes: 0 };
  if (dryRun) {
    const { data, error } = await client.rpc("orphan_product_images", {
      p_min_age: SWEEP_MIN_AGE,
      p_limit: PAGE,
    });
    const orphans = error ? null : orphansFrom(data);
    if (!orphans) return { ...summary, ok: false, error: "server_error" };
    return {
      ...summary,
      files: orphans.length,
      bytes: orphans.reduce((s, o) => s + o.bytes, 0),
      names: orphans.map((o) => o.name),
    };
  }
  for (let pass = 0; pass < MAX_PASSES; pass++) {
    const { data, error } = await client.rpc("orphan_product_images", {
      p_min_age: SWEEP_MIN_AGE,
      p_limit: PAGE,
    });
    const orphans = error ? null : orphansFrom(data);
    if (!orphans) return { ...summary, ok: false, error: "server_error" };
    if (orphans.length === 0) return summary;
    for (let i = 0; i < orphans.length; i += REMOVE_CHUNK) {
      const chunk = orphans.slice(i, i + REMOVE_CHUNK);
      const removed = await client.storage.from("product-images").remove(
        chunk.map((o) => o.name),
      );
      if (removed.error) return { ...summary, ok: false, error: "remove_failed" };
      summary.files += chunk.length;
      summary.bytes += chunk.reduce((s, o) => s + o.bytes, 0);
    }
    if (orphans.length < PAGE) return summary;
  }
  return summary;
}
