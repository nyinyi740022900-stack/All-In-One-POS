// Shared Ed25519 offline-license-token signing — used by both the admin
// console's manual "sign_offline" action (admin/index.ts, for hand-fulfilling
// a shop with no connectivity at all) and activate's automatic issuance on
// every successful key activation / shop signup (activate/index.ts), so a
// Premium shop always has a cryptographic fallback that outlives the online
// grace window, not just shops an admin happened to fulfill by hand.
//
// See lib/features/license/offline_license.dart for the client-side
// verifier and the "MMPOS1.<payload>.<sig>" token format.

import * as ed from "https://esm.sh/@noble/ed25519@2.1.0";

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

export interface SignOfflineTokenParams {
  shopId: string;
  shopName?: string | null;
  plan?: string;
  /** Validity window in months from now. Defaults to 1 — short enough that
   * an auto-issued fallback token refreshes routinely via the client's
   * 6-hour silent re-verify while online, long enough to comfortably outlive
   * the 7-day online grace window if connectivity is lost. Admin-issued
   * tokens for a genuinely offline shop pass an explicit, longer value. */
  months?: number;
  deviceId?: string;
}

export interface SignedOfflineToken {
  token: string;
  expiresAt: string; // ISO 8601
}

/** Throws Error("signing_key_missing") if LICENSE_SIGNING_KEY_HEX isn't
 * configured, or Error("bad_request") for an empty shopId — callers map
 * these to their own error response shape. */
export async function signOfflineToken(
  params: SignOfflineTokenParams,
): Promise<SignedOfflineToken> {
  const keyHex = Deno.env.get("LICENSE_SIGNING_KEY_HEX");
  if (!keyHex) throw new Error("signing_key_missing");
  const shopId = params.shopId.trim();
  if (!shopId) throw new Error("bad_request");

  const months = params.months ?? 1;
  const now = Math.floor(Date.now() / 1000);
  const exp = now + months * 30 * 24 * 3600;
  const payload: Record<string, unknown> = {
    shop_id: shopId,
    shop_name: params.shopName ?? null,
    plan: params.plan ?? "monthly",
    exp,
    iat: now,
  };
  const deviceId = (params.deviceId ?? "").trim();
  if (deviceId) payload.device_id = deviceId;

  const payloadB64 = b64url(
    new TextEncoder().encode(JSON.stringify(payload)),
  );
  const message = new TextEncoder().encode("MMPOS1." + payloadB64);
  const priv = hexToBytes(keyHex);
  const sig = await ed.signAsync(message, priv);
  const token = "MMPOS1." + payloadB64 + "." + b64url(sig);
  return { token, expiresAt: new Date(exp * 1000).toISOString() };
}
