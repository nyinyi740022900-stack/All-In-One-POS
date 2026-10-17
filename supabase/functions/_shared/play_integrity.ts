// Play Integrity for the Android calls that grant a trial or a Premium
// receipt (see GATED_ACTIONS). Owner decisions, 2026-10-17:
//  - only those calls, only for Android;
//  - a GitHub APK signed with our upload key passes ("pass_sideload"), and a
//    phone without Google Play services is let through and logged
//    ("unavailable") — device integrity (root checks) is NOT required;
//  - start in "monitor" mode (log every verdict, block nothing); the admin
//    flips app_config `integrity.android_mode` to "enforce" after the beta.
//
// Limits, plainly: this guards what the SERVER hands out. A patched app that
// never calls the server can still unlock screens gated only on the phone;
// the client signature check and obfuscation are what slow that down. And a
// client can claim to be iOS/web — App Attest is the follow-up for that.

export const PACKAGE_NAME = "com.allinonepos.app";

/** Our upload key — what local, CI and GitHub-released APKs are signed with
 * (matches lib/core/integrity/app_integrity.dart). */
export const UPLOAD_CERT_SHA256 =
  "A80738070C8D447FEB1F6B1CF1EC3CDA897F5914EC623F99506BE8D79F43AFE4";

export const GATED_ACTIONS = new Set([
  "refresh_account_license",
  "resync_session",
  "switch_branch",
  "start_trial",
]);

/** First app build that sends attestation. Older Android builds sending
 * nothing are not "missing" — they predate the feature. */
export const FIRST_ATTESTING_BUILD = 9;

/** How old a token's request may be. */
export const MAX_TOKEN_AGE_MS = 10 * 60 * 1000;

export type Verdict =
  | "pass" // installed from Play, our app
  | "pass_sideload" // not from Play, but signed with our upload key
  | "fail" // re-signed / wrong package / wrong request / stale / replayed
  | "unavailable" // the phone couldn't produce a token (no Play services…)
  | "missing" // an attesting build sent no token and no reason
  | "not_configured" // server has no Google credentials yet
  | "not_android"
  | "error"; // Google API or our own failure — never the user's fault

export interface IntegrityResult {
  verdict: Verdict;
  reason?: string;
  appVerdict?: string;
  deviceVerdict?: string;
  licensingVerdict?: string;
  versionCode?: number;
}

export type IntegrityMode = "monitor" | "enforce";

/** The request hash the app put into the token: binds it to this action,
 * this device and a one-time nonce. Lower-case hex SHA-256. */
export async function requestHash(
  action: string,
  deviceId: string,
  nonce: string,
): Promise<string> {
  const data = new TextEncoder().encode(
    `aiopos.pi.v1|${action}|${deviceId}|${nonce}`,
  );
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function b64urlToHex(s: string): string {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const pad = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  const bin = atob(pad);
  return [...bin].map((c) => c.charCodeAt(0).toString(16).padStart(2, "0"))
    .join("").toUpperCase();
}

// deno-lint-ignore no-explicit-any
type Payload = any;

/** Judges a decoded token payload. Pure, so it is unit-tested directly. */
export function evaluatePayload(
  payload: Payload,
  expectedHash: string,
  now: number,
): IntegrityResult {
  const app = payload?.appIntegrity ?? {};
  const base: IntegrityResult = {
    verdict: "fail",
    appVerdict: app.appRecognitionVerdict,
    deviceVerdict: (payload?.deviceIntegrity?.deviceRecognitionVerdict ?? [])
      .join(","),
    licensingVerdict: payload?.accountDetails?.appLicensingVerdict,
    versionCode: app.versionCode ? Number(app.versionCode) : undefined,
  };
  const req = payload?.requestDetails;
  if (!req) return { ...base, reason: "no_request_details" };
  if (req.requestPackageName !== PACKAGE_NAME) {
    return { ...base, reason: "package" };
  }
  if (req.requestHash !== expectedHash) {
    return { ...base, reason: "request_hash" };
  }
  const at = Number(req.timestampMillis);
  if (!Number.isFinite(at) || Math.abs(now - at) > MAX_TOKEN_AGE_MS) {
    return { ...base, reason: "stale" };
  }
  switch (app.appRecognitionVerdict) {
    case "PLAY_RECOGNIZED":
      return { ...base, verdict: "pass" };
    case "UNRECOGNIZED_VERSION": {
      const certs: string[] = (app.certificateSha256Digest ?? []).map(
        b64urlToHex,
      );
      return certs.includes(UPLOAD_CERT_SHA256)
        ? { ...base, verdict: "pass_sideload" }
        : { ...base, reason: "certificate" };
    }
    case "UNEVALUATED":
      return { ...base, verdict: "unavailable", reason: "unevaluated" };
    default:
      return { ...base, reason: "app_verdict" };
  }
}

/** Whether the call may go on. Monitor mode never blocks. */
export function allowCall(
  mode: IntegrityMode,
  result: IntegrityResult,
  appBuild: number,
): boolean {
  if (mode !== "enforce") return true;
  if (result.verdict === "fail") return false;
  if (result.verdict === "missing") return appBuild < FIRST_ATTESTING_BUILD;
  return true;
}

export function parseMode(raw: unknown): IntegrityMode {
  return String(raw ?? "").trim().toLowerCase() === "enforce"
    ? "enforce"
    : "monitor";
}

// ── Google API ─────────────────────────────────────────────────────────────

interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

function serviceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("PLAY_INTEGRITY_SA_JSON");
  if (!raw) return null;
  try {
    const sa = JSON.parse(raw);
    return sa?.client_email && sa?.private_key ? sa : null;
  } catch {
    return null;
  }
}

function b64url(bytes: Uint8Array | string): string {
  const bin = typeof bytes === "string"
    ? bytes
    : [...bytes].map((b) => String.fromCharCode(b)).join("");
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let cachedToken: { value: string; expiresAt: number } | null = null;

async function googleAccessToken(
  sa: ServiceAccount,
  fetchFn: typeof fetch,
): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt - 60_000 > now) {
    return cachedToken.value;
  }
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const iat = Math.floor(now / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/playintegrity",
    aud: tokenUri,
    iat,
    exp: iat + 3600,
  }));
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  );
  const res = await fetchFn(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${header}.${claims}.${b64url(signature)}`,
    }),
  });
  if (!res.ok) throw new Error(`oauth_${res.status}`);
  const data = await res.json();
  cachedToken = {
    value: data.access_token,
    expiresAt: now + Number(data.expires_in ?? 3600) * 1000,
  };
  return cachedToken.value;
}

/** Full check for one gated call. Never throws. */
export async function checkIntegrity(
  body: Record<string, unknown>,
  action: string,
  deviceId: string,
  fetchFn: typeof fetch = fetch,
  now = Date.now(),
): Promise<IntegrityResult> {
  const platform = String(body.platform ?? "");
  if (platform !== "android") return { verdict: "not_android" };
  const token = typeof body.integrity_token === "string"
    ? body.integrity_token
    : "";
  const nonce = typeof body.integrity_nonce === "string"
    ? body.integrity_nonce
    : "";
  if (!token) {
    const why = typeof body.integrity_error === "string"
      ? body.integrity_error.slice(0, 80)
      : "";
    return why
      ? { verdict: "unavailable", reason: why }
      : { verdict: "missing" };
  }
  if (!nonce) return { verdict: "fail", reason: "no_nonce" };
  const sa = serviceAccount();
  if (!sa) return { verdict: "not_configured" };
  try {
    const access = await googleAccessToken(sa, fetchFn);
    const res = await fetchFn(
      `https://playintegrity.googleapis.com/v1/${PACKAGE_NAME}:decodeIntegrityToken`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${access}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ integrity_token: token }),
      },
    );
    if (res.status === 400) return { verdict: "fail", reason: "undecodable" };
    if (!res.ok) return { verdict: "error", reason: `decode_${res.status}` };
    const data = await res.json();
    return evaluatePayload(
      data.tokenPayloadExternal,
      await requestHash(action, deviceId, nonce),
      now,
    );
  } catch (e) {
    return {
      verdict: "error",
      reason: (e instanceof Error ? e.message : "exception").slice(0, 80),
    };
  }
}
