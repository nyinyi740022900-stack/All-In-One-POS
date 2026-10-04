export interface SocialProof {
  provider: "google" | "apple";
  token: string;
  access_token?: string;
  nonce?: string;
}
export type SocialVerifier = (proof: SocialProof) => Promise<string | null>;
export type ProofConsumer = (
  hash: string,
  expiresAt: string,
) => Promise<boolean>;

/** Only inspect token times AFTER Supabase has validated its signature and user. */
export async function verifySocialReauthentication(
  callerId: string,
  body: Record<string, unknown>,
  verify: SocialVerifier,
  consume: ProofConsumer,
  now = Date.now(),
): Promise<boolean> {
  if (
    (body.provider !== "google" && body.provider !== "apple") ||
    typeof body.id_token !== "string" || !body.id_token.trim()
  ) return false;
  const proof: SocialProof = { provider: body.provider, token: body.id_token };
  for (const key of ["access_token", "nonce"] as const) {
    if (typeof body[key] === "string" && body[key]) proof[key] = body[key];
  }
  try {
    if (await verify(proof) !== callerId) return false;
    const encoded = proof.token.split(".")[1];
    const claims = JSON.parse(
      atob(encoded.replace(/-/g, "+").replace(/_/g, "/")),
    );
    const seconds = now / 1000;
    if (
      typeof claims.iat !== "number" || !Number.isFinite(claims.iat) ||
      claims.iat < seconds - 300 || claims.iat > seconds + 60 ||
      typeof claims.exp !== "number" || !Number.isFinite(claims.exp) ||
      claims.exp <= seconds
    ) return false;
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(proof.token),
    );
    const hash = Array.from(
      new Uint8Array(digest),
      (b) => b.toString(16).padStart(2, "0"),
    ).join("");
    return await consume(
      hash,
      new Date(Math.min(claims.exp, claims.iat + 300) * 1000).toISOString(),
    );
  } catch {
    return false;
  }
}
