# Native Google and Apple login setup

Provider buttons are disabled by default. Google OAuth has not yet been set up
for this project. Live provider login is therefore **unverified**. The native
packages are pinned to Google Sign-In 7.2.0 and Sign in with Apple 8.2.0.
No credentials, Apple capability or signing identity have been invented.

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
Apple is shown only on iOS. Browser/admin/desktop builds keep these choices
hidden. An enable flag is a deployment assertion that native/server setup is
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

No Google callback scheme is shipped while the client ID is unknown. Android
SDK configuration errors can surface as cancellation; persistent cancellation
after account selection requires checking package/fingerprint/web-client setup.

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
