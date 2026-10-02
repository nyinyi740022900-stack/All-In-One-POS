// Server-signed entitlement receipt — the proof the app checks before it
// unlocks Premium.
//
// Why this exists: the app caches the shop's plan and expiry on the phone, and
// a plain JSON cache can be edited (a rooted device, a restored backup) to
// push the expiry out. The server now signs {shop, plan, expiry, issued-at}
// with an Ed25519 key it alone holds; the app verifies that signature with the
// public key baked into `lib/features/license/entitlement.dart` and ignores
// any cached expiry that doesn't match one.
//
// This is NOT an offline licence code. Nobody types or sends it, it can't be
// minted for a shop that has no licence row, and it carries the licence's REAL
// expiry (the removed offline token was valid 30 days from issue regardless).
// Buying or renewing still needs the internet once, exactly as before.
//
// Bound to the shop, not the device: a receipt copied between phones only
// grants the same shop's own Premium, and binding to a device would force every
// branch-switch / resync payload to carry a device id it doesn't have today.
//
// Token: "AIOE1.<base64url(payload)>.<base64url(signature)>", the signature
// being over the ASCII string "AIOE1." + base64url(payload).
//
// Secret: ENTITLEMENT_SIGNING_KEY_HEX (32-byte Ed25519 seed, hex). If it isn't
// set the field is simply omitted and the app treats the plan as Free — it
// fails closed, never open.

import * as ed from "https://esm.sh/@noble/ed25519@2.1.0";

const PREFIX = "AIOE1.";

function b64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.substr(i * 2, 2), 16);
  }
  return out;
}

export interface EntitlementInput {
  shopId: string;
  plan: string;
  /** The licence's own expiry, ISO 8601. */
  expiresAt: string;
}

/** Returns the signed token, or undefined when it can't be issued (no signing
 * key, no shop, or an unparseable expiry). Never throws. */
export async function signEntitlement(
  input: EntitlementInput,
): Promise<string | undefined> {
  try {
    const keyHex = Deno.env.get("ENTITLEMENT_SIGNING_KEY_HEX");
    if (!keyHex) return undefined;
    const shopId = (input.shopId ?? "").trim();
    const expMs = Date.parse(input.expiresAt);
    if (!shopId || Number.isNaN(expMs)) return undefined;
    const payload = {
      v: 1,
      shop_id: shopId,
      plan: input.plan,
      exp: Math.floor(expMs / 1000),
      iat: Math.floor(Date.now() / 1000),
    };
    const payloadB64 = b64url(new TextEncoder().encode(JSON.stringify(payload)));
    const message = new TextEncoder().encode(PREFIX + payloadB64);
    const sig = await ed.signAsync(message, hexToBytes(keyHex));
    return PREFIX + payloadB64 + "." + b64url(sig);
  } catch (_) {
    return undefined;
  }
}

/** Adds `entitlement` (and the server clock as `server_time`, so the app can
 * pin its own clock to a trusted one) to a licence response body. Leaves the
 * body untouched when it has no shop or expiry to attest. */
export async function withEntitlement(
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const shopId = body.shop_id as string | undefined;
  const expiresAt = body.expires_at as string | null | undefined;
  if (!shopId || !expiresAt) return body;
  const entitlement = await signEntitlement({
    shopId,
    plan: String(body.plan ?? "monthly"),
    expiresAt,
  });
  return {
    ...body,
    entitlement,
    server_time: new Date().toISOString(),
  };
}
