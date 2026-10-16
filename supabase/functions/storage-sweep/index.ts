// Deletes product photos no product or storefront points at any more —
// replaced photos and the like — once they are 30 days old. Shop receipt
// logos are never touched (see migration 0104 for every rule that keeps a
// file).
//
// Intended to be called once a day by Supabase's scheduled jobs with the
// service-role key, like `expiry-reminders`. Deployed with JWT verification
// ON (the default), and refuses anything but the service role, so the anon
// key that ships in the app cannot start a deletion. `?dry_run=1` lists what
// a run would remove without removing it; `?wait=1` blocks for the summary.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type SweepClient, sweepOrphanPhotos } from "../_shared/photo_sweep.ts";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!isServiceRole(req)) return json({ error: "forbidden" }, 403);

  const params = new URL(req.url).searchParams;
  const dryRun = params.get("dry_run") === "1";
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  ) as unknown as SweepClient;
  const run = sweepOrphanPhotos(admin, { dryRun });

  // The scheduler gives up after 5 s; answer it at once and let the runtime
  // finish (same reasoning as expiry-reminders).
  if (dryRun || params.get("wait") === "1") {
    const summary = await run;
    return json(summary, summary.ok ? 200 : 503);
  }
  EdgeRuntime.waitUntil(
    run.then((s) => console.log("storage sweep:", JSON.stringify(s))),
  );
  return json({ ok: true, accepted: true }, 202);
});

function isServiceRole(req: Request): boolean {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const body = token.split(".")[1];
  if (!body) return false;
  try {
    const pad = body.length % 4 ? "=".repeat(4 - (body.length % 4)) : "";
    const claims = JSON.parse(
      atob(body.replace(/-/g, "+").replace(/_/g, "/") + pad),
    );
    return claims?.role === "service_role";
  } catch {
    return false;
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
