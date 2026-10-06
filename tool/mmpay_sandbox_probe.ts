#!/usr/bin/env -S deno run --allow-env --allow-net --allow-read
//
// Drives `_shared/mmpay.ts` against MMPay's SANDBOX from this machine, so the
// protocol can be proven before anything is wired to a live project. Keys come
// from the gitignored `mmpay.local.json`; they are never printed, and nothing
// here touches Supabase.
//
//   deno run --allow-env --allow-net --allow-read tool/mmpay_sandbox_probe.ts
//
// What it answers:
//   - does handshake → create → get → cancel work with our own client?
//   - Q8: is `PaymentResponse.url` a hosted payment page, or absent?
//   - what does an order actually look like, field by field?
import { mmpayConfig } from "../supabase/functions/_shared/mmpay_mode.ts";
import {
  cancelPayment,
  compactOrderId,
  createPayment,
  getPayment,
} from "../supabase/functions/_shared/mmpay.ts";

const keys = JSON.parse(await Deno.readTextFile("mmpay.local.json"));
for (const [name, value] of Object.entries(keys)) {
  Deno.env.set(name, `${value}`);
}
// A non-production host, so the mode guard permits sandbox. This is exactly
// the check that stops this script ever being pointed at live money.
Deno.env.set("SUPABASE_URL", "https://local-probe.supabase.co");
Deno.env.set("MMPAY_TEST_MODE", "true");

const cfg = mmpayConfig();
if ("error" in cfg) {
  console.error(`configuration refused: ${cfg.error}`);
  console.error("Paste the sandbox pk_test_/sk_test_ pair into mmpay.local.json.");
  Deno.exit(1);
}
console.log(`app ${cfg.appId} · sandbox · ${cfg.baseUrl}`);

// Shaped like the real thing: the billing_checkouts row id, compacted to the
// 32 characters MMPay allows.
const checkoutId = crypto.randomUUID();
const orderId = compactOrderId(checkoutId);
const amount = 20000;

async function step<T>(name: string, run: () => Promise<T>): Promise<T | null> {
  try {
    const value = await run();
    console.log(`\n=== ${name} ===`);
    console.log(JSON.stringify(value, null, 2));
    return value;
  } catch (error) {
    console.error(`\n=== ${name} FAILED ===`);
    console.error(error instanceof Error ? error.message : error);
    return null;
  }
}

const created = await step(
  `create ${orderId} for ${amount} MMK`,
  () =>
    createPayment(cfg, {
      orderId,
      amount,
      customMessage: "All In One POS Premium - 1 month",
    }),
);
if (!created) Deno.exit(1);

console.log(`\ncheckout id ${checkoutId} -> order id ${orderId}`);
console.log(`QR string: ${created.qr ? `${created.qr.length} chars` : "(absent)"}`);
console.log(`Q8 — hosted url field: ${"url" in created.raw ? created.raw.url : "(absent — render the QR ourselves)"}`);

await step("get (before payment)", () => getPayment(cfg, orderId));
await step("cancel", () => cancelPayment(cfg, orderId));
await step("get (after cancel)", () => getPayment(cfg, orderId));
