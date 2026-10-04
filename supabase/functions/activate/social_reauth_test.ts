function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
import { verifySocialReauthentication } from "./social_reauth.ts";
const now = 1800000000000;
function token(iat = now / 1000) {
  return `header.${btoa(JSON.stringify({ iat, exp: iat + 3600 }))}.signature`;
}
async function check(
  body: Record<string, unknown>,
  verified: string | null = "u",
  consume: (hash: string, expiresAt: string) => Promise<boolean> = async () =>
    true,
) {
  return await verifySocialReauthentication(
    "u",
    body,
    async () => verified,
    consume,
    now,
  );
}
Deno.test("fresh upstream verified same-user Google and Apple proof is accepted", async () => {
  for (const provider of ["google", "apple"]) {
    assert(
      await check({ provider, id_token: token(), nonce: "raw-nonce" }),
      "must accept verified same-user fresh proof",
    );
  }
});
Deno.test("mismatched reauthentication identity is rejected", async () => {
  assert(
    !await check({ provider: "google", id_token: token() }, "other"),
    "must reject another account",
  );
});
Deno.test("invalid upstream proof cannot trust unsigned token timestamps", async () => {
  assert(
    !await check({ provider: "apple", id_token: token() }, null),
    "must require upstream validation",
  );
});
Deno.test("stale future and malformed verified timestamps are rejected", async () => {
  for (
    const id_token of [
      token(now / 1000 - 301),
      token(now / 1000 + 61),
      "not-a-token",
    ]
  ) {
    assert(
      !await check({ provider: "google", id_token }),
      "must require a fresh signed timestamp",
    );
  }
});
Deno.test("accepted reauthentication cannot replay a consumed proof", async () => {
  const hashes = new Set();
  const consume = async (hash: string) => {
    if (hashes.has(hash)) return false;
    hashes.add(hash);
    return true;
  };
  const proof = { provider: "google", id_token: token() };
  assert(await check(proof, "u", consume), "first proof must work");
  assert(!await check(proof, "u", consume), "proof must be single use");
});
Deno.test("unsupported or absent provider credentials cannot authenticate deletion", async () => {
  for (
    const proof of [{ provider: "facebook", id_token: token() }, {
      provider: "google",
    }, { id_token: token() }]
  ) assert(!await check(proof), "must require supported credentials");
});
