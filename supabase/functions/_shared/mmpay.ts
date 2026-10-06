// A small MMPay client on fetch + Web Crypto, deliberately NOT the published
// `mmpay-node-sdk`. That package is about sixty lines of value wrapped in
// defects we would be importing straight into the money path:
//
//   - every method ends `catch (error) { return error as any }`, so a failed
//     pay() returns an error object typed as a success;
//   - handShake() swallows too, so a failed handshake leaves the token
//     undefined and the payment call proceeds with `X-Mmpay-Btoken: undefined`;
//   - verifyCb compares signatures with `!==` (not timing-safe) and never
//     looks at the nonce, so a captured callback replays forever;
//   - sandbox-versus-production is decided by substring-matching the key.
//
// Here, errors throw, every call is bounded, the signature comparison is
// timing-safe, and replay is bounded by a nonce window on top of the database
// idempotency. The server decides the mode (see mmpay_mode.ts).
import type { MmpayConfig } from "./mmpay_mode.ts";

/// MMPay's own terminal vocabulary (`POST /payments/get`).
export type MmpayStatus =
  | "PENDING"
  | "SUCCESS"
  | "FAILED"
  | "REFUNDED"
  | "CANCELLED"
  | "EXPIRED";

/// `condition` is explicitly NOT part of the grant decision. `SUCCESS` with
/// `condition: TOUCHED` means the QR was scanned again, not that a second
/// payment happened — the SDK routes that to onHeartbeat, which is how an
/// integration listening only for success misses a re-scanned QR entirely.
export interface MmpayPayment {
  /// Present on `get` only; `create` and `cancel` answer without it.
  appId: string;
  orderId: string;
  amount: number;
  status: MmpayStatus;
  condition?: string;
  /// The EMVCo MMQR string. There is no hosted payment page — confirmed
  /// against the sandbox 2026-10-06 — so the surface renders this itself.
  qr?: string;
  transactionRefId?: string;
  raw: Record<string, unknown>;
}

/// MMPay caps `orderId` at 32 characters and a UUID with hyphens is 36, so the
/// `billing_checkouts` row id travels as its 32 hex digits and is expanded back
/// on the way in. Lossless both ways, and still unique per attempt forever.
export function compactOrderId(checkoutId: string): string {
  return checkoutId.replace(/-/g, "").toLowerCase();
}

export function expandOrderId(orderId: string): string | null {
  const hex = orderId.trim().toLowerCase();
  if (!/^[0-9a-f]{32}$/.test(hex)) return null;
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join("-");
}

export class MmpayError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    readonly retryable: boolean,
  ) {
    super(code);
    this.name = "MmpayError";
  }
}

const TIMEOUT_MS = 15000;

/// Every call is two round trips: a one-time handshake token, then the real
/// POST carrying it as `X-Mmpay-Btoken`. Each leg is bounded separately, so a
/// hung MMPay costs at most 30 seconds rather than a spinner that never ends.
async function handshake(
  cfg: MmpayConfig,
  orderId: string,
  nonce: string,
): Promise<string> {
  const result = await post(cfg, "handshake", { orderId, nonce }, nonce, null);
  const token = `${result.token ?? ""}`;
  if (!token) throw new MmpayError("mmpay_handshake_failed", 502, true);
  return token;
}

/// The nonce is NOT just a header: it has to appear in the signed body too,
/// with the same value, or the handshake answers `KA0003`. The published docs
/// do not say so; only the SDK source does.
function begin(orderId: string): string {
  if (orderId.length > 32) {
    throw new MmpayError("mmpay_order_id_too_long", 400, false);
  }
  return `${Date.now()}`;
}

export async function createPayment(
  cfg: MmpayConfig,
  input: {
    orderId: string;
    amount: number;
    customMessage?: string;
    callbackUrl?: string;
  },
): Promise<MmpayPayment> {
  const nonce = begin(input.orderId);
  const token = await handshake(cfg, input.orderId, nonce);
  // Exactly the fields the API validates. It rejects a body it does not
  // recognise, so `currency` is NOT sent — the account is MMK and the response
  // says so itself.
  const raw = await post(cfg, "create", {
    appId: cfg.appId,
    nonce,
    amount: input.amount,
    orderId: input.orderId,
    callbackUrl: input.callbackUrl,
    customMessage: input.customMessage,
  }, nonce, token);
  return toPayment(raw);
}

export async function getPayment(
  cfg: MmpayConfig,
  orderId: string,
): Promise<MmpayPayment> {
  const nonce = begin(orderId);
  const token = await handshake(cfg, orderId, nonce);
  return toPayment(await post(cfg, "get", { orderId, nonce }, nonce, token));
}

export async function cancelPayment(
  cfg: MmpayConfig,
  orderId: string,
): Promise<MmpayPayment> {
  const nonce = begin(orderId);
  const token = await handshake(cfg, orderId, nonce);
  return toPayment(
    await post(cfg, "cancel", { orderId, nonce }, nonce, token),
  );
}

function toPayment(raw: Record<string, unknown>): MmpayPayment {
  const status = `${raw.status ?? ""}`.toUpperCase();
  const amount = Number(raw.amount);
  if (!STATUSES.has(status) || !Number.isFinite(amount)) {
    throw new MmpayError("mmpay_unreadable_response", 502, false);
  }
  return {
    appId: `${raw.appId ?? ""}`,
    orderId: `${raw.orderId ?? ""}`,
    amount,
    status: status as MmpayStatus,
    condition: raw.condition == null ? undefined : `${raw.condition}`,
    qr: typeof raw.qr === "string" ? raw.qr : undefined,
    transactionRefId: raw.transactionRefId == null
      ? undefined
      : `${raw.transactionRefId}`,
    raw,
  };
}

const STATUSES = new Set<string>([
  "PENDING",
  "SUCCESS",
  "FAILED",
  "REFUNDED",
  "CANCELLED",
  "EXPIRED",
]);

/// Terminal and unpaid: the order can never become money, so its reservation
/// may be closed and the owner offered a fresh QR.
export function isDead(status: MmpayStatus): boolean {
  return status === "FAILED" || status === "CANCELLED" || status === "EXPIRED";
}

async function post(
  cfg: MmpayConfig,
  endpoint: "handshake" | "create" | "get" | "cancel",
  body: Record<string, unknown>,
  nonce: string,
  btoken: string | null,
): Promise<Record<string, unknown>> {
  const path = `/payments/${cfg.testMode ? "sandbox-" : ""}${endpoint}`;
  const payload = JSON.stringify(body);
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    // The publishable key identifies; the secret key signs.
    "Authorization": `Bearer ${cfg.publishableKey}`,
    "X-Mmpay-Nonce": nonce,
    "X-Mmpay-Signature": await sign(cfg.secretKey, nonce, payload),
  };
  if (btoken) headers["X-Mmpay-Btoken"] = btoken;
  let response: Response;
  try {
    response = await fetch(`${cfg.baseUrl}${path}`, {
      method: "POST",
      headers,
      body: payload,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch {
    // Unknown outcome. The caller must NOT close a reservation on this: a
    // retried POST against an order that did get created is how one shop ends
    // up holding two payable QRs.
    throw new MmpayError("mmpay_unavailable", 502, true);
  }
  let parsed: unknown;
  try {
    parsed = await response.json();
  } catch {
    throw new MmpayError("mmpay_unreadable_response", 502, !response.ok);
  }
  const data = (parsed ?? {}) as Record<string, unknown>;
  if (!response.ok) {
    // KA0001 bearer missing, KA0002 key not LIVE, KA0005 IP not whitelisted —
    // all definitive refusals that no retry will fix.
    const code = `${data.mmpayErrorCode ?? data.errorCode ?? "mmpay_rejected"}`;
    throw new MmpayError(code, response.status, response.status >= 500);
  }
  // Some endpoints answer `{data: {...}}`, some answer flat.
  const inner = data.data;
  return (inner && typeof inner === "object")
    ? inner as Record<string, unknown>
    : data;
}

/// `HMAC_SHA256(secretKey, `${nonce}.${body}`)` as lowercase hex, which is the
/// construction MMPay uses in both directions.
export async function sign(
  secretKey: string,
  nonce: string,
  body: string,
): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secretKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(`${nonce}.${body}`));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// How far out of date a *timestamp* nonce may be.
///
/// Outbound, MMPay's nonce is `Date.now()`. **Inbound it is not**: a real
/// sandbox callback arrives with `X-Mmpay-Nonce: e7c6d2d9c095aa69` — sixteen
/// opaque hex characters, observed 2026-10-06. An earlier version of this
/// function required a timestamp inside this window and so rejected every
/// genuine callback with 401. The window is therefore applied only when the
/// nonce actually looks like epoch milliseconds, which keeps the protection if
/// MMPay ever switches to one and does not invent a rule they do not follow.
const NONCE_WINDOW_MS = 10 * 60 * 1000;

/// Shape of an opaque nonce: hex, long enough not to be guessable, short
/// enough not to be a smuggled payload.
const OPAQUE_NONCE = /^[0-9a-f]{8,64}$/i;

/// Replay, with an opaque nonce, is bounded by the database rather than by
/// this function: the signature covers `nonce.body`, the body carries the
/// order id, and that order id is uniquely indexed and keyed by payment id —
/// so a captured callback can only ever re-deliver its own order, which grants
/// nothing a second time. It can never be retargeted at another order, because
/// changing a byte of the body invalidates the signature.
export async function verifyCallback(
  secretKey: string,
  raw: string,
  signatureHex: string,
  nonce: string,
  now = Date.now(),
): Promise<boolean> {
  if (!signatureHex || !nonce) return false;
  if (/^\d{10,}$/.test(nonce)) {
    const sent = Number(nonce);
    if (!Number.isFinite(sent) || Math.abs(now - sent) > NONCE_WINDOW_MS) {
      return false;
    }
  } else if (!OPAQUE_NONCE.test(nonce)) {
    return false;
  }
  const expected = await sign(secretKey, nonce, raw);
  return timingSafeEqualHex(expected, signatureHex.trim().toLowerCase());
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
