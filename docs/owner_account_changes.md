# Owner email and Google changes

Settings → Account offers owner-only account changes. The backend owner role and local Owner PIN mode gate the controls. Shop ownership, memberships, trial usage, Premium receipts and the three-device entitlement continue to refer to the same Auth user ID. No local synced table or SettingsRepository key changes.

## Email

Change email requests Supabase secure email confirmation with the native `allinonepos://login-callback` redirect. Confirm the old and new inbox messages before checking the new address in the app. Changing the primary email does not replace a Google identity or add a password to a social-only account. Existing saved login autofill is cleared when a change is requested.

The email transport uses an isolated Auth client. It adopts the result only if the originating user and bearer are still current; timeout or a late response cannot overwrite another owner's session.

## Google

On configured native platforms, link the replacement Google account first. After successful verification, remove the old Google identity. The replacement must not already belong to another POS Auth user; this flow does not merge separate accounts. Removing the sole identity or retaining only an unconfirmed fallback is blocked. A verified Google, Apple or email identity must remain. Google linking snapshots the owner before the native chooser and refuses to mutate auth if the session changes while choosing.

Supabase production `Allow manual linking` is currently OFF; enabling it requires explicit approval of the access-setting change. `Secure email change` and `Confirm email` are ON. Google is configured on Android; iOS Google is hidden until its provider/client prerequisites are configured. This change does not enable iOS Google alone or modify store commerce flags.

## Ripple check

- `currentAccountEmailProvider` observes auth events; account UI observes the same stream.
- Email-based staff matching applies only to backend staff sessions; owner email changes cannot grant staff roster capabilities.
- Renewal shop/history/billing authorization uses `owner_user_id`, not email. Future checkout prefills use the current owner email; an existing processor subscription may retain its own billing contact email.
- No license reattach, trial start, branch switch, local wipe or membership reassignment occurs.
- No per-device/per-shop settings key was added.

## Validation / pending live checks

Focused tests cover sole/verified fallback policy, owner role, unchanged membership/license, email bearer and pending response, switched-owner isolation, chooser session changes, EN/Myanmar errors and duplicate-submit prevention. `flutter analyze` is clean and all 1,049 Flutter tests pass. The release iPhone build completed (45 seconds), installed and launched successfully on the paired iPhone. Commerce remains at its default disabled value. Real inbox/provider account smoke is pending. Production custom SMTP is OFF and no send-email Auth hook is configured; delivery to arbitrary owner inboxes requires a custom SMTP provider (default Supabase SMTP is restricted to organization team addresses). No confirmation mail was sent.

For a designated real owner: confirm both inboxes, refresh the account screen, sign in again with the new email (email-password accounts), and verify both owned shops and Premium. On Android link a spare Google identity, sign in with it, verify the same user/shops, then remove the old identity and confirm the new one still works. These checks require the owner to select/confirm credentials; no real owner credentials or account were changed by the agent.

References: [Supabase identity linking](https://supabase.com/docs/guides/auth/auth-identity-linking), [SMTP delivery requirements](https://supabase.com/docs/guides/auth/auth-smtp).
