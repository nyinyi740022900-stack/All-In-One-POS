import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  allowCall,
  checkIntegrity,
  evaluatePayload,
  FIRST_ATTESTING_BUILD,
  MAX_TOKEN_AGE_MS,
  PACKAGE_NAME,
  parseMode,
  requestHash,
  UPLOAD_CERT_SHA256,
} from "../_shared/play_integrity.ts";

const NOW = 1_800_000_000_000;

function hexToB64url(hex: string): string {
  const bytes = hex.match(/../g)!.map((h) => parseInt(h, 16));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-")
    .replace(/\//g, "_").replace(/=+$/, "");
}

async function payload(over: Record<string, unknown> = {}) {
  return {
    requestDetails: {
      requestPackageName: PACKAGE_NAME,
      requestHash: await requestHash("start_trial", "dev-1", "n-1"),
      timestampMillis: String(NOW - 5_000),
    },
    appIntegrity: {
      appRecognitionVerdict: "PLAY_RECOGNIZED",
      packageName: PACKAGE_NAME,
      versionCode: "9",
    },
    deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] },
    accountDetails: { appLicensingVerdict: "LICENSED" },
    ...over,
  };
}

const HASH = await requestHash("start_trial", "dev-1", "n-1");

Deno.test("request hash matches the app (lib/core/integrity/play_integrity.dart)", () => {
  // Same literal as test/play_integrity_test.dart.
  assertEquals(
    HASH,
    "a5f3fe98bae2579439b48ef23593bff89f4ec12a40bfe51ce7e45973c98df3e9",
  );
});

Deno.test("a Play install of our app passes", async () => {
  const r = evaluatePayload(await payload(), HASH, NOW);
  assertEquals(r.verdict, "pass");
  assertEquals(r.versionCode, 9);
  assertEquals(r.deviceVerdict, "MEETS_DEVICE_INTEGRITY");
});

Deno.test("a GitHub APK signed with our upload key passes as sideload", async () => {
  const p = await payload({
    appIntegrity: {
      appRecognitionVerdict: "UNRECOGNIZED_VERSION",
      certificateSha256Digest: [hexToB64url(UPLOAD_CERT_SHA256)],
    },
  });
  assertEquals(evaluatePayload(p, HASH, NOW).verdict, "pass_sideload");
});

Deno.test("a re-signed copy fails on its certificate", async () => {
  const p = await payload({
    appIntegrity: {
      appRecognitionVerdict: "UNRECOGNIZED_VERSION",
      certificateSha256Digest: [hexToB64url("00".repeat(32))],
    },
  });
  const r = evaluatePayload(p, HASH, NOW);
  assertEquals([r.verdict, r.reason], ["fail", "certificate"]);
});

Deno.test("a token made for another call, app or time fails", async () => {
  for (
    const [over, reason] of [
      [{ requestHash: "beef" }, "request_hash"],
      [{ requestPackageName: "com.evil.app" }, "package"],
      [{ timestampMillis: String(NOW - MAX_TOKEN_AGE_MS - 1) }, "stale"],
    ] as const
  ) {
    const base = await payload();
    const r = evaluatePayload(
      { ...base, requestDetails: { ...base.requestDetails, ...over } },
      HASH,
      NOW,
    );
    assertEquals([r.verdict, r.reason], ["fail", reason]);
  }
});

Deno.test("an unevaluated app is unavailable, not a failure", async () => {
  const p = await payload({
    appIntegrity: { appRecognitionVerdict: "UNEVALUATED" },
  });
  assertEquals(evaluatePayload(p, HASH, NOW).verdict, "unavailable");
});

Deno.test("monitor never blocks; enforce blocks only real failures", () => {
  for (const v of ["fail", "missing", "unavailable", "error"] as const) {
    assertEquals(allowCall("monitor", { verdict: v }, 9), true, v);
  }
  assertEquals(allowCall("enforce", { verdict: "fail" }, 9), false);
  assertEquals(allowCall("enforce", { verdict: "pass" }, 9), true);
  assertEquals(allowCall("enforce", { verdict: "pass_sideload" }, 9), true);
  // Owner call: a phone without Play services is let through.
  assertEquals(allowCall("enforce", { verdict: "unavailable" }, 9), true);
  assertEquals(allowCall("enforce", { verdict: "not_configured" }, 9), true);
  assertEquals(allowCall("enforce", { verdict: "error" }, 9), true);
  // Builds before attestation shipped send nothing — not their fault.
  assertEquals(
    allowCall("enforce", { verdict: "missing" }, FIRST_ATTESTING_BUILD - 1),
    true,
  );
  assertEquals(
    allowCall("enforce", { verdict: "missing" }, FIRST_ATTESTING_BUILD),
    false,
  );
});

Deno.test("mode defaults to monitor for anything but 'enforce'", () => {
  assertEquals(parseMode(undefined), "monitor");
  assertEquals(parseMode(""), "monitor");
  assertEquals(parseMode("ENFORCE "), "enforce");
  assertEquals(parseMode("block"), "monitor");
});

Deno.test("checkIntegrity: platform, missing, unavailable, not configured", async () => {
  Deno.env.delete("PLAY_INTEGRITY_SA_JSON");
  const noFetch = (() => {
    throw new Error("must not call Google");
  }) as unknown as typeof fetch;
  assertEquals(
    (await checkIntegrity({ platform: "ios" }, "start_trial", "d", noFetch))
      .verdict,
    "not_android",
  );
  assertEquals(
    (await checkIntegrity({ platform: "android" }, "start_trial", "d", noFetch))
      .verdict,
    "missing",
  );
  const unavailable = await checkIntegrity(
    { platform: "android", integrity_error: "PLAY_SERVICES_NOT_FOUND" },
    "start_trial",
    "d",
    noFetch,
  );
  assertEquals(
    [unavailable.verdict, unavailable.reason],
    ["unavailable", "PLAY_SERVICES_NOT_FOUND"],
  );
  assertEquals(
    (await checkIntegrity(
      { platform: "android", integrity_token: "t", integrity_nonce: "n" },
      "start_trial",
      "d",
      noFetch,
    )).verdict,
    "not_configured",
  );
});

Deno.test("checkIntegrity decodes through Google with a service account", async () => {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const pkcs8 = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...pkcs8))
  }\n-----END PRIVATE KEY-----\n`;
  Deno.env.set(
    "PLAY_INTEGRITY_SA_JSON",
    JSON.stringify({ client_email: "v@p.iam.gserviceaccount.com", private_key: pem }),
  );
  const decoded = await payload();
  const calls: string[] = [];
  const fakeFetch = (async (url: string | URL, init?: RequestInit) => {
    calls.push(String(url));
    if (String(url).includes("oauth2")) {
      const assertion = new URLSearchParams(String(init?.body)).get("assertion")!;
      const [h, c, sig] = assertion.split(".");
      const raw = Uint8Array.from(
        atob(sig.replace(/-/g, "+").replace(/_/g, "/") + "==".slice(0, (4 - sig.length % 4) % 4)),
        (ch) => ch.charCodeAt(0),
      );
      const ok = await crypto.subtle.verify(
        "RSASSA-PKCS1-v1_5",
        pair.publicKey,
        raw,
        new TextEncoder().encode(`${h}.${c}`),
      );
      assertEquals(ok, true, "JWT must be signed with the service-account key");
      return new Response(JSON.stringify({ access_token: "at", expires_in: 3600 }));
    }
    assertEquals(
      String(url),
      `https://playintegrity.googleapis.com/v1/${PACKAGE_NAME}:decodeIntegrityToken`,
    );
    assertEquals(
      (init?.headers as Record<string, string>).Authorization,
      "Bearer at",
    );
    return new Response(JSON.stringify({ tokenPayloadExternal: decoded }));
  }) as typeof fetch;
  const r = await checkIntegrity(
    {
      platform: "android",
      integrity_token: "token",
      integrity_nonce: "n-1",
    },
    "start_trial",
    "dev-1",
    fakeFetch,
    NOW,
  );
  assertEquals(r.verdict, "pass");
  assertEquals(calls.length, 2);
  Deno.env.delete("PLAY_INTEGRITY_SA_JSON");
});
