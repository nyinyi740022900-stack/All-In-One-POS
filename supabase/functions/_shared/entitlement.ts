// Version 2 server-signed account/shop/device Premium receipt.
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
  userId: string;
  deviceId: string;
  revision: number;
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
    if (!keyHex || !/^[0-9a-fA-F]{64}$/.test(keyHex)) return undefined;
    const shopId = (input.shopId ?? "").trim();
    const expMs = Date.parse(input.expiresAt);
    if (
      !shopId || !input.userId?.trim() || !input.deviceId?.trim() ||
      !Number.isSafeInteger(input.revision) || input.revision < 1 ||
      !["monthly", "yearly", "trial"].includes(input.plan) ||
      Number.isNaN(expMs)
    ) return undefined;
    const payload = {
      v: 2,
      user_id: input.userId,
      device_id: input.deviceId,
      revision: input.revision,
      shop_id: shopId,
      plan: input.plan,
      exp: Math.floor(expMs / 1000),
      iat: Math.floor(Date.now() / 1000),
    };
    const payloadB64 = b64url(
      new TextEncoder().encode(JSON.stringify(payload)),
    );
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
    plan: String(body.plan ?? "free"),
    userId: String(body.user_id ?? ""),
    deviceId: String(body.device_id ?? ""),
    revision: Number(body.revision),
    expiresAt,
  });
  return {
    ...body,
    entitlement,
    server_time: new Date().toISOString(),
  };
}
