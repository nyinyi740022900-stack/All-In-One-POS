# Google and Apple login — approved design

Owner approved the proposed design with “ok” on 2026-10-04. Google Cloud OAuth has not yet been configured. Implement the complete code and verification first, with providers hidden until valid configuration is supplied. Do not expose failing provider buttons or invent credentials. Use the existing shared codex/account-premium branch and preserve all concurrent edits.

## User experience

Android uses native Google account selection. iPhone supports native Google and Apple. Email/password remains available. Add provider choices to onboarding, daily entry and Shop Login. A first social account needs only a shop name and creates a Free shop; trial remains explicit. Existing verified-email identities retain their existing user/shop/Premium. Signed-in users can link a different Google/Apple identity explicitly. Staff never becomes an owner through social sign-up. Different real shops retain the existing outbox/confirmation/DB-switch safeguards. Cancellation is silent, failures localized, busy states prevent repeated actions.

## Authentication boundary

Provider tokens are verified by Supabase, not by email/name comparisons in Flutter. Apple uses a secure raw nonce and SHA-256 nonce sent to Apple. Secrets remain server-side. Local owner PIN behavior is unchanged. Provider visibility depends on native platform and deployment configuration; setup is a separate required delivery prerequisite.

## Shared interfaces

`social_auth.dart`: `enum SocialAuthProvider { google, apple }`; `SocialAuthFailure(code)`; `SocialAuthProof(provider, idToken, {accessToken, nonce})` with `toRequest()` producing provider/id_token/access_token/nonce; `SocialAuthService.availableProviders`, `signIn(provider)`, `link(provider)`, `reauthenticate(provider)` (returns proof without replacing app session). It is injectable in AccountRepository as optional `socialAuth`.

`AccountActionResult.needsShopName()` adds `needsShopName`; other constructors default false. AccountRepository exposes `availableSocialProviders`, `linkedSocialProviders`, `hasPasswordIdentity`, `signInWithSocial(provider)`, `completeSocialSignup(shopName)`, `linkSocialIdentity(provider)`, `deleteAccountWithSocial(provider)`. Cancellation uses error `auth_cancelled`, absent setup `social_auth_unavailable`.

Server `prepare_social_account` verifies real-account user, resolves existing authoritative membership, updates trusted metadata and returns `{ok:true,needs_shop_name:false,shop_id}`; unprovisioned users get `{ok:true,needs_shop_name:true}`. Existing/revoked staff must not gain owner rights. `signup_social_shop` is an idempotent first-shop operation with a per-user transaction lock; registered owners reuse their shop; staff/revoked/archived membership cannot create an owner shop. Respond with subscriptionReply; client refreshes JWT and attaches the device before applying license.

`delete_account` accepts password as today OR fresh verified social proof. Verify proof through Supabase provider authentication in a separate client, require resulting auth user id to equal caller id, and retain existing owner/data-deletion checks. Provider proof never grants a role. Tests must reject different-user proof and replay/stale proof where fresh proof is required.

## Release

Analyze clean, full Flutter tests, Deno checks/tests, migration staging verification before production. Changelog in PROJECT_SPEC. Build/install app only after checks and compatible backend readiness. Actual provider login requires Google OAuth clients/Supabase settings and Apple capability/provider configuration. Do not mark live social login complete before those are configured and exercised.
