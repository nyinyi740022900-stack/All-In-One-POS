# Google and Apple login setup

Provider buttons are disabled by default. **As of 2026-10-07 Google is
configured on web, Android and iOS, and the consent screen is published.**
Apple configuration remains pending. The native packages are pinned to
Google Sign-In 7.2.0 and Sign in with Apple 8.2.0.

**The thing that silently breaks everything:** the OAuth consent screen's
publishing status. It sat at **Testing with zero test users**, which means
*nobody* could sign in with Google — on any platform. The button rendered, the
flow started, and Google refused the account. It is now **In production**, so
any Google account works. If Google sign-in ever stops working for everyone at
once, check Google Auth Platform → Audience first; nothing in this repo will
show you that.

Google Cloud project **`solid-groove-510702-p8`** ("All In One POS"), owned by a
different Google account from the one that may be signed into a browser by
default — the credentials page 404s with a permissions error under the wrong
account, which looks like a missing project rather than a wrong login.

## Build configuration

Supply these public settings through the existing ignored `env.local.json` or
`--dart-define` options:

| Setting | Default | Required before enabling |
| --- | --- | --- |
| `GOOGLE_AUTH_ENABLED` | false | Google native clients, callback scheme and Supabase provider verified |
| `GOOGLE_WEB_CLIENT_ID` | empty | Google **Web application** OAuth client ID, passed as `serverClientId` |
| `GOOGLE_IOS_CLIENT_ID` | empty | OAuth iOS client for `com.allinonepos.app` |
| `APPLE_AUTH_ENABLED` | false | Apple capability/profile and Supabase Apple provider verified |

The app also requires the existing Supabase URL and anon key. Native Google is
shown only on Android/iOS; iOS additionally requires its iOS client ID. Native
Apple is shown only on iOS. Admin/desktop builds keep these choices
hidden. Renewal web uses a separate Supabase browser OAuth flow when
`GOOGLE_AUTH_ENABLED` is true; it does not use the native Google plugin. An enable flag is a deployment assertion that native/server setup is
ready; it cannot automatically verify the cloud console or signing profile.

## Google

1. Create a Google Cloud project and OAuth consent screen for All In One POS.
   Configure audience/test users and the OpenID, email and profile scopes.
2. Create a **Web application** OAuth client. Set the project's actual Supabase
   callback URI from Authentication → Providers → Google. Configure its client
   ID and secret in Supabase; the secret must remain server-side. Add native
   client IDs to the allowed client-ID list, keeping the web ID first. See
   [Supabase Google setup](https://supabase.com/docs/guides/auth/social-login/auth-google).
3. Create an **Android** OAuth client using package `com.allinonepos.app` and
   the SHA-1 certificate fingerprint for each relevant signing identity:
   local debug, release/upload, and Google Play app signing. Obtain the latter
   from Play Console's App integrity page. Register every signing identity
   actually used for testing/distribution. This implementation supplies the
   web ID directly and does not require `google-services.json` or the Google
   services Gradle plugin. See the
   [official Android plugin setup](https://pub.dev/packages/google_sign_in_android).
4. Create an **iOS** OAuth client for bundle `com.allinonepos.app`. Put its ID
   in `GOOGLE_IOS_CLIENT_ID`. Add a separate dictionary to the existing
   `CFBundleURLTypes` array in `ios/Runner/Info.plist`, with
   `CFBundleURLSchemes` containing the real reversed iOS client ID. For a real
   ID ending in `.apps.googleusercontent.com`, reversing its dot components
   gives `com.googleusercontent.apps.<actual-client-prefix>`. Copy the exact
   `REVERSED_CLIENT_ID` if Google provides it. Preserve existing app URL
   schemes. Do not add an empty scheme or the example placeholder. The plugin
   receives `clientId`/`serverClientId` in Dart, so `GIDClientID` and
   `GIDServerClientID` plist entries are unnecessary. See the
   [official iOS plugin setup](https://pub.dev/packages/google_sign_in_ios).
5. Rebuild after configuration. Enable `GOOGLE_AUTH_ENABLED` only for the
   configured deployment; validate native account selection and Supabase
   token verification in staging first. No extra Google data scopes or access
   authorization are requested by this app.

The iOS callback scheme **is** now shipped: `Info.plist` carries the reversed
client ID beside the app's own `allinonepos`/`mmpos` schemes. Note the gate in
`SocialAuthService.availableProviders` — on iOS the Google button is hidden
unless `GOOGLE_IOS_CLIENT_ID` is non-empty, so a build made without
`--dart-define-from-file=env.local.json` simply shows no button rather than
failing at tap time. That is deliberate, and it is also the first thing to
check when the button is missing.

Android SDK configuration errors can surface as cancellation; persistent
cancellation after account selection requires checking
package/fingerprint/web-client setup.

**Supabase needs nothing per-platform.** The Dart code passes
`serverClientId: GOOGLE_WEB_CLIENT_ID`, so every ID token is minted for the web
client regardless of platform, and that one client ID is already in the
provider's Client IDs list. Do not add the iOS or Android client IDs there.

## Apple (native iOS only)

1. Use the existing paid Apple Developer team and App ID
   `com.allinonepos.app`. Enable Sign in with Apple for that App ID and obtain
   a matching development/distribution provisioning profile. Preserve the
   existing bundle ID and signing team.
2. Enable Apple in Supabase Auth and register `com.allinonepos.app` in its
   allowed client IDs for native identity tokens. Native-only login does not
   require a web Services ID or six-month OAuth client-secret rotation. If a
   web OAuth flow is later added, configure its Services ID, callback and
   signing secret server-side separately. See
   [Supabase Apple setup](https://supabase.com/docs/guides/auth/social-login/auth-apple).
3. Copy `ios/Flutter/SocialAuth.example.xcconfig` to
   `ios/Flutter/SocialAuth.local.xcconfig`, then uncomment
   `CODE_SIGN_ENTITLEMENTS = Runner/SocialAuth.entitlements`. Debug, Release
   and Profile (which reuses Release configuration) pick it up. The local
   selection is ignored by git. Configure this same selection explicitly on
   the release build machine. `Runner/SocialAuth.entitlements` contains only
   the Sign in with Apple capability; if future capabilities add entitlements,
   merge them into the selected file before switching files.
4. Set `APPLE_AUTH_ENABLED=true` only after the selected profile supports the
   entitlement. Rebuild and test on a real iPhone. The default build includes
   no Apple entitlement and keeps Apple hidden, so the existing development
   provisioning remains usable.

Apple gets the SHA-256 hash of a freshly generated secure nonce. Supabase gets
its original raw value. Name/email returned by Apple never determines local
role or membership; first social shop creation asks for the shop name. Apple
may only return name/email the first time consent is granted. See
[Apple plugin integration](https://pub.dev/packages/sign_in_with_apple/versions/8.2.0).

## Identity linking and release verification

Enable manual identity linking in the Supabase Authentication configuration
before offering explicit linking. This is a separate readiness requirement from
turning on Google or Apple: provider activation alone does not enable manual
linking. Verify the server setting and same-user linking in staging before
shipping the linking UI. Supabase verifies credentials; matching
emails are not a client-side account-linking policy. See
[Supabase linking API](https://supabase.com/docs/reference/dart/auth-linkidentitywithidtoken).

**Live status (2026-10-08): still OFF on the production project.** The toggle is
Supabase dashboard → Authentication → Sign In / Providers → User Signups →
*Allow manual linking*. Until it is on, Account → "Link another Google account"
fails at `linkIdentityWithIdToken`, and the only error the owner sees is the
generic "Something went wrong" (`manual_linking_disabled` is not mapped in
`account_action_error.dart`). Signing in with Google on a matching, already
verified email is a different path — that one goes through `signInWithIdToken`
and does not depend on this setting.

After staging backend migration/functions and provider configuration, verify:

- New account → shop name → one Free shop, without an automatic trial.
- Existing verified-email owner → existing shop/subscription; staff keeps role.
- Explicit linking → same Supabase user ID, including rejection of identities
  already attached elsewhere.
- Different real shop → existing switch confirmation/outbox safeguards.
- Cancel each native sheet → no error or local account transition.
- Apple hidden-email account works; sign-out/relogin keeps authoritative shop.
- Social account deletion requests fresh provider proof, rejects a different
  provider user and stale/replayed proof, and never switches the app session.
- Android debug/release/Play signatures and iOS signed distribution each work.

Token acquisition uses fresh native authentication, not a cached Supabase
session. Google uses the interactive native flow (not lightweight/cached auth).
Include deletion reauthentication after a session has been open for more than
five minutes in live staging verification; the server enforces proof age.
Reauthentication returns proof only; backend validation enforces the
caller match/freshness. Provider dialogs remain open until the user completes
or cancels. Initialization and Supabase network exchanges are bounded to 30
seconds. The token exchange runs in an isolated, non-persistent auth client
with bounded HTTP reads and owned socket cleanup. Only a timely verified,
sufficiently unexpired response is adopted into the main session using the
public local-session API. Same-user linking and the original session snapshot
are checked before adoption; a late response cannot replace the app session.
Provider credentials/error descriptions are never logged.


## Renewal website Google login

The owner can use **Continue with Google** at
https://shop.allinonepos.app/renew with the same Google account used in the POS
app. The browser has its own persisted session; mobile login is not automatically
shared. Existing verified-email identity linking is handled by Supabase Auth,
not by matching emails in our billing code.

The exact production callback `https://shop.allinonepos.app/renew` was added to
Supabase Authentication → URL Configuration on 2026-10-05. Keep the native
`allinonepos://login-callback` URL. Do not allow arbitrary preview domains or
wildcards. The Google Cloud client's authorized redirect remains Supabase's
`/auth/v1/callback`; the app return URL belongs in Supabase's allowlist.

After session restoration/sign-in, `prepare_social_account` resolves the
existing membership server-side, then the browser refreshes its JWT before
loading owner shops. It does not call signup, trial, or device attachment and
does not consume one of the three device slots. Accounts without owner shops
see existing app setup guidance; revoked/archived membership stays blocked.
Late results cannot refill a signed-out/replaced account's shop or history.

Release smoke: open `/renew`, choose Google, sign in as an existing owner,
verify the original shop and request history, sign out, and verify private shop
data disappears. Repeat with a Google account without a shop and a staff
account; neither should see a purchase form. No real payment is needed to
verify login. Processor checkout testing is a separate owner-authorized step.

Verification (2026-10-05): analyzer clean, 1034 Flutter tests pass, production
web script matches the verified build. The live button reaches Google account
selection with PKCE and the exact `/renew` return URL. Owner selection and
post-login shop/history verification remain a human smoke step.
