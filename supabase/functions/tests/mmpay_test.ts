import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const { mmpayAvailable, mmpayConfig, mmpayTestMode } = await import(
  "../_shared/mmpay_mode.ts"
);
const { isDead, sign, verifyCallback } = await import("../_shared/mmpay.ts");

const PRODUCTION_URL = "https://gnikispsurwrmkspuisj.supabase.co";
const STAGING_URL = "https://staging.supabase.co";

function withEnv(env: Record<string, string | null>, body: () => void) {
  const previous = new Map<string, string | undefined>();
  for (const [key, value] of Object.entries(env)) {
    previous.set(key, Deno.env.get(key));
    if (value === null) Deno.env.delete(key);
    else Deno.env.set(key, value);
  }
  try {
    body();
  } finally {
    for (const [key, value] of previous) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

const SANDBOX = {
  SUPABASE_URL: STAGING_URL,
  MMPAY_TEST_MODE: "true",
  MMPAY_APP_ID: "MM57179826",
  MMPAY_PUBLISHABLE_KEY: "pk_test_abc",
  MMPAY_SECRET_KEY: "sk_test_abc",
  MMPAY_BASE_URL: null,
};

Deno.test("sandbox mode needs a non-production project", () => {
  withEnv({ SUPABASE_URL: STAGING_URL, MMPAY_TEST_MODE: "true" }, () => {
    assertEquals(mmpayTestMode(), true);
  });
  withEnv({ SUPABASE_URL: STAGING_URL, MMPAY_TEST_MODE: null }, () => {
    assertEquals(mmpayTestMode(), false);
  });
});

Deno.test("a sandbox flag on production throws rather than charging play money", () => {
  withEnv({ SUPABASE_URL: PRODUCTION_URL, MMPAY_TEST_MODE: "true" }, () => {
    assertThrows(() => mmpayTestMode(), Error, "test_mode_not_allowed");
    assertEquals(mmpayAvailable(), false);
  });
});

Deno.test("an unidentifiable project is treated as production", () => {
  withEnv({ SUPABASE_URL: "not a url", MMPAY_TEST_MODE: "true" }, () => {
    assertThrows(() => mmpayTestMode(), Error, "test_mode_not_allowed");
  });
});

Deno.test("the server decides the mode, not the key's own prefix", () => {
  // A live key pasted into a sandbox project is the mistake MMPay's own SDK
  // cannot catch: it decides sandbox-vs-live by substring-matching the key,
  // so it would happily start taking real money from a staging deployment.
  withEnv({ ...SANDBOX, MMPAY_SECRET_KEY: "sk_live_abc" }, () => {
    const cfg = mmpayConfig();
    assertEquals("error" in cfg && cfg.error, "mmpay_key_wrong_mode");
  });
  withEnv({ ...SANDBOX, MMPAY_PUBLISHABLE_KEY: "pk_live_abc" }, () => {
    const cfg = mmpayConfig();
    assertEquals("error" in cfg && cfg.error, "mmpay_key_wrong_mode");
  });
  // And the reverse: sandbox keys on a production-mode project.
  withEnv({
    SUPABASE_URL: PRODUCTION_URL,
    MMPAY_TEST_MODE: null,
    MMPAY_APP_ID: "MM57179826",
    MMPAY_PUBLISHABLE_KEY: "pk_test_abc",
    MMPAY_SECRET_KEY: "sk_test_abc",
  }, () => {
    const cfg = mmpayConfig();
    assertEquals("error" in cfg && cfg.error, "mmpay_key_wrong_mode");
  });
});

Deno.test("a missing secret makes MMQR unavailable instead of half-configured", () => {
  withEnv({ ...SANDBOX, MMPAY_SECRET_KEY: null }, () => {
    const cfg = mmpayConfig();
    assertEquals("error" in cfg && cfg.error, "mmpay_not_configured");
    assertEquals(mmpayAvailable(), false);
  });
  withEnv(SANDBOX, () => {
    assertEquals(mmpayAvailable(), true);
    const cfg = mmpayConfig();
    assertEquals("error" in cfg, false);
    if (!("error" in cfg)) {
      assertEquals(cfg.baseUrl, "https://ezapi.myanmyanpay.com");
      assertEquals(cfg.testMode, true);
    }
  });
});

Deno.test("a plaintext base URL is refused", () => {
  withEnv({ ...SANDBOX, MMPAY_BASE_URL: "http://ezapi.myanmyanpay.com" }, () => {
    const cfg = mmpayConfig();
    assertEquals("error" in cfg && cfg.error, "mmpay_not_configured");
  });
});

Deno.test("only FAILED, CANCELLED and EXPIRED release a reservation", () => {
  assertEquals(isDead("FAILED"), true);
  assertEquals(isDead("CANCELLED"), true);
  assertEquals(isDead("EXPIRED"), true);
  // REFUNDED is terminal but the money DID arrive — releasing the reservation
  // would offer a second QR for a term already granted.
  assertEquals(isDead("REFUNDED"), false);
  assertEquals(isDead("SUCCESS"), false);
  assertEquals(isDead("PENDING"), false);
});

Deno.test("a correctly signed callback verifies", async () => {
  const raw = '{"orderId":"abc","status":"SUCCESS"}';
  const nonce = `${Date.now()}`;
  const signature = await sign("sk_test_abc", nonce, raw);
  assertEquals(
    await verifyCallback("sk_test_abc", raw, signature, nonce),
    true,
  );
  // Uppercase hex is still the same signature.
  assertEquals(
    await verifyCallback("sk_test_abc", raw, signature.toUpperCase(), nonce),
    true,
  );
});

Deno.test("a tampered body, nonce, key or signature does not verify", async () => {
  const raw = '{"orderId":"abc","status":"SUCCESS","amount":20000}';
  const nonce = `${Date.now()}`;
  const signature = await sign("sk_test_abc", nonce, raw);
  const cases: Array<[string, Promise<boolean>]> = [
    ["amount raised", verifyCallback(
      "sk_test_abc",
      raw.replace("20000", "20001"),
      signature,
      nonce,
    )],
    ["nonce swapped", verifyCallback("sk_test_abc", raw, signature, `${Number(nonce) - 1}`)],
    ["wrong secret", verifyCallback("sk_test_other", raw, signature, nonce)],
    ["signature missing", verifyCallback("sk_test_abc", raw, "", nonce)],
    ["nonce missing", verifyCallback("sk_test_abc", raw, signature, "")],
  ];
  for (const [name, result] of cases) {
    assertEquals(await result, false, name);
  }
});

Deno.test("a captured callback stops replaying once its nonce ages out", async () => {
  // MMPay's own verifier never looks at the nonce, so without this window a
  // captured callback is replayable forever.
  const raw = '{"orderId":"abc","status":"SUCCESS"}';
  const now = Date.now();
  const nonce = `${now}`;
  const signature = await sign("sk_test_abc", nonce, raw);
  assertEquals(
    await verifyCallback("sk_test_abc", raw, signature, nonce, now + 9 * 60 * 1000),
    true,
  );
  assertEquals(
    await verifyCallback("sk_test_abc", raw, signature, nonce, now + 11 * 60 * 1000),
    false,
  );
  // A clock that runs the other way is just as suspect.
  assertEquals(
    await verifyCallback("sk_test_abc", raw, signature, nonce, now - 11 * 60 * 1000),
    false,
  );
  assertEquals(
    await verifyCallback("sk_test_abc", raw, signature, "not-a-number", now),
    false,
  );
});

Deno.test("an unreadable MMPay response throws instead of being read as success", async () => {
  // The published SDK returns the error object typed as a success here. This
  // client throws, so a malformed answer can never reach the fulfilment RPC.
  const { createPayment } = await import("../_shared/mmpay.ts");
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (() =>
    Promise.resolve(
      new Response(JSON.stringify({ status: "NOT_A_STATUS", amount: 20000 }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    )) as typeof fetch;
  try {
    const cfg = {
      appId: "MM57179826",
      publishableKey: "pk_test_abc",
      secretKey: "sk_test_abc",
      baseUrl: "https://ezapi.myanmyanpay.com",
      testMode: true,
    };
    await assertRejects(
      () => createPayment(cfg, { orderId: "abc", amount: 20000 }),
      Error,
      "mmpay_handshake_failed",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
