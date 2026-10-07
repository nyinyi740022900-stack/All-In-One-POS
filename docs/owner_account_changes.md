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

## Confirmation callback fix and bilingual template (2026-10-05)

Owner screenshots confirm mail arrived for the tested addresses. They also show an `otp_expired` rejection (used/invalid/expired link), followed by missing native callback and `/` routes. This is evidence of mail delivery for those addresses, not proof of delivery to every shop owner or of completed email change. The app now normalizes native callback URLs to a status-only route, strips tokens/server descriptions from routing, preserves SDK verification and gives local EN/Myanmar recovery guidance. Home `/` redirects to Sell. Callback status contains no shop data and may show before a daily PIN; returning to Shop still requires all normal gates. Password and license auth listeners handle rejected links without unhandled errors; no Premium is granted or cleared.

Bilingual template: `supabase/templates/change_email.html` with subject/deployment notes in its README. Both languages appear in one mail. It keeps the per-inbox `ConfirmationURL`, current/new addresses, both-inbox instructions and a single action. Production UI explicitly blocks template customization on the current Free/default SMTP setup: configure custom SMTP or upgrade to Pro. No subscription, SMTP credential, template deployment or real confirmation link was submitted. Existing emails retain their previous template.

Callback regression tests cover invalid/used links, valid callback payload stripping, malformed fragments, foreign schemes, root Home navigation, and production callback-versus-daily-PIN gates. Analyzer clean; all 1,054 Flutter tests pass. Mobile email preview inspected at 390 px width. Release build installed and launched successfully on the paired iPhone with commerce disabled. The custom SMTP/template live-mail test is still pending; no sent mail was modified.

## Mail delivery: Resend domain, SMTP and the reset-password template (2026-10-06)

**Sending domain is verified.** `auth.allinonepos.app` was added to Resend on
2026-10-05 20:57 and verified at 21:11 — DNS at Namecheap, sending region Tokyo
(`ap-northeast-1`), opportunistic TLS. `dig` confirms SPF
(`send.auth.allinonepos.app`) and DKIM (`resend._domainkey.auth.allinonepos.app`)
resolve. The "Pending" state the previous session stopped on has cleared; no DNS
record was added or changed in this pass.

**DMARC is missing** on both `auth.allinonepos.app` and the root
`allinonepos.app`. SPF and DKIM alone deliver, but Gmail and Yahoo treat an
absent DMARC policy as a negative signal. Recommended Namecheap TXT record on
the root domain, host `_dmarc`:
`v=DMARC1; p=none; rua=mailto:dmarc@allinonepos.app`. Start at `p=none`, read the
reports, tighten later. Not added here — it is a DNS change on the owner's
registrar account.

**Supabase SMTP is staged, not saved.** Authentication → Emails → SMTP Settings
now has the toggle on and every non-secret field filled: sender
`noreply@auth.allinonepos.app`, sender name `All In One POS`, host
`smtp.resend.com`, port 587, username `resend`. The Password field is a Resend
API key and was deliberately left empty — a production API key is not something
this session types into a remote dashboard. Nothing was saved, so the live
project is still on default Supabase SMTP until the owner pastes the key and
presses Save changes. The dashboard notes that enabling custom SMTP raises the
auth mail rate limit to 30/hour.

The key to create in Resend: **Sending access**, restricted to
`auth.allinonepos.app`. The two keys already in that account (`Theorylane`,
`Onboarding`) belong to other projects and predate this domain — do not reuse
them.

**Redirect URLs verified.** The project's allow list holds
`allinonepos://login-callback` and `https://shop.allinonepos.app/renew`, so both
the reset-password and change-email links resolve into the app once mail is
flowing.

**New: `supabase/templates/reset_password.html`.** Auditing which Auth mails this
product actually sends turned up a gap — only *change email* had a bilingual
template, but `forgot_password_dialog.dart` calls `resetPasswordForEmail` and is
live today, so once custom SMTP is on that mail would still go out as the default
English Supabase body. The new template matches `change_email.html`: Myanmar and
English in one message, `{{ .ConfirmationURL }}` / `{{ .Email }}` preserved,
inline tables, no JavaScript, tracking, image or font dependency, and an explicit
"your shops, sales records and Premium are unchanged" line. Preview inspected at
390 px. Signup sends no mail (`email_confirm: true` server-side); magic link,
invite and reauthentication are unused and stay at their defaults.

Still pending, in order: create the scoped Resend key → paste it into the staged
SMTP form and save → deploy both templates under Authentication → Emails →
Templates (editing unlocks once custom SMTP is on) → send a real reset and a real
email change to an owner inbox and confirm both-inbox completion. Add DMARC
alongside. No Dart changed in this pass; analyzer clean and all 1,054 tests pass.

## Mail delivery, second pass (2026-10-07)

Nothing was saved last time, so the live project is unchanged: **custom SMTP is
still off** and the staged form had evaporated, as an unsaved form does. It has
been staged again — sender `noreply@auth.allinonepos.app`, name `All In One
POS`, host `smtp.resend.com`, port 587, username `resend` — with the Password
field empty and **not saved**, because a Resend API key is not something this
session types into a remote dashboard. The Resend API keys page is open in the
next tab; the two keys listed there (`Theorylane`, `Onboarding`) belong to other
projects and predate this domain.

DNS re-checked: SPF and DKIM still resolve, **DMARC is still absent** on both
`auth.allinonepos.app` and the root.

Two things this pass established that the first one had not:

**Templates really are gated on SMTP.** The Templates tab says outright "Set up
custom SMTP to edit templates" and offers no editor at all until then — so the
order is SMTP first, templates second, with no way around it on this plan.

**Supabase has security-notification emails of its own**, which the first audit
missed because it only looked at what the app's own code triggers: *Password
changed*, *Email address changed*, *Phone number changed*, *Sign-in method
linked*, *Sign-in method removed*, *MFA method added*, *MFA method removed*.
**All seven are off**, so switching SMTP on does not start sending them. That
matters because two of them map onto flows this product genuinely has — the
owner email change, and Google identity linking — so enabling either later
without writing a bilingual body first would send Supabase's English default to
a Myanmar shop owner.

Remaining, unchanged: create the scoped Resend key and paste it into the staged
form, deploy both templates, send a real reset and a real email change to an
owner inbox, and add the DMARC record at the registrar.

## Mail delivery is live (2026-10-07)

**Custom SMTP is on and a real email has been delivered.** Resend SMTP
(`smtp.resend.com:587`, username `resend`, sender
`noreply@auth.allinonepos.app`), both bilingual templates deployed, and a
genuine password-reset mail accepted by Supabase (`HTTP 200`) and reported
**Delivered** by Resend to a real inbox, with the Myanmar subject intact:
`All In One POS — စကားဝှက်အသစ် သတ်မှတ်ရန် / Reset your password`.

### The first attempt failed, and the test is what caught it

Saving the SMTP form is not proof it works. The first send returned
`HTTP 500 "Error sending recovery email"`, and the auth log gave the reason:

```
535 "Authentication credentials invalid"
```

Resend's own logs showed **nothing at all**, which places the failure before
Resend ever saw a message — an SMTP AUTH rejection, not a send rejection. The
host was independently confirmed fine (`smtp.resend.com:587` reachable,
STARTTLS, `AUTH PLAIN LOGIN`), so the only remaining variable was the password.

Most likely cause, worth knowing for next time: the API keys table shows each
token **truncated** (`re_HNRufF8b…`), and copying from there yields a key that
is not the key. The full value appears only once, at creation. Creating a fresh
key and pasting that worked immediately.

**Diagnosing this again:** Supabase → Logs → Auth, find the `ERROR /recover`
row, open **Raw** — the SMTP error string is in `event_message.error`. The
Details tab alone only shows status 500, which tells you nothing.

### Still open

- **DMARC.** Still absent on `auth.allinonepos.app` and the root. SPF and DKIM
  carry delivery today — this mail reached an iCloud inbox — but Gmail and
  Yahoo read a missing policy as a negative signal. At the registrar, TXT on the
  root, host `_dmarc`: `v=DMARC1; p=none; rua=mailto:dmarc@allinonepos.app`.
- **A real email change**, end to end, through both inboxes. Only the reset
  mail has actually been sent.
- The superseded `All In One POS auth` key in Resend can be deleted.
