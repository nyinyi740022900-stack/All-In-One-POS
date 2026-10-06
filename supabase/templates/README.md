# Bilingual auth email templates

Two Supabase Auth mails are sent by this product, and both have a bilingual
(Myanmar + English, one message) body here:

| File | Supabase template | Triggered by |
| --- | --- | --- |
| `change_email.html` | **Change email address** | `owner_email_transport.dart` → `updateUser(email:)` (Shop → Account) |
| `reset_password.html` | **Reset password** | `forgot_password_dialog.dart` → `resetPasswordForEmail` |

Signup sends no mail: `signup_shop` provisions with `email_confirm: true` on the
server, deliberately, so a shop is never stranded on opening day waiting for
SMTP. Magic link, invite and reauthentication are unused — leave those
templates at their defaults.

## Subjects

- Change email — `All In One POS — အီးမေးလ်ပြောင်းလဲမှု အတည်ပြုရန် / Confirm email change`
- Reset password — `All In One POS — စကားဝှက်အသစ် သတ်မှတ်ရန် / Reset your password`

## Template rules

Keep `{{ .ConfirmationURL }}`, `{{ .Email }}` and (change-email only)
`{{ .NewEmail }}` unchanged. Supabase supplies a separate confirmation URL for
each inbox while Secure email change is on. Never replace the action with a
hard-coded native callback; that would skip verification. No secret, real owner
address or live token is stored in these files. Inline table layout, system
fonts; no JavaScript, external tracking, font/image dependency or attachment.

Both links open the app through `allinonepos://login-callback/`, which is in the
project's Redirect URLs allow list alongside `https://shop.allinonepos.app/renew`.
The app shows safe invalid/used-link guidance. Clicking a one-time link twice can
be rejected; a rejection does not prove the original request failed — check the
current account email in Shop → Account before requesting another change.

## Delivery — Resend SMTP

Template editing on this project's plan is unlocked only once custom SMTP is on,
so SMTP comes first.

Sending domain `auth.allinonepos.app` is **verified** in Resend (added and
verified 2026-10-05, DNS at Namecheap, sending region Tokyo `ap-northeast-1`,
opportunistic TLS). SPF and DKIM (`resend._domainkey`) resolve.

Supabase → Authentication → Emails → SMTP Settings:

| Field | Value |
| --- | --- |
| Sender email address | `noreply@auth.allinonepos.app` |
| Sender name | `All In One POS` |
| Host | `smtp.resend.com` |
| Port | `587` |
| Username | `resend` |
| Password | a Resend API key — **Sending access**, restricted to `auth.allinonepos.app` |

Enabling custom SMTP raises the auth mail rate limit to 30/hour; raise it under
Authentication → Rate Limits if real signups ever need more.

**Known gap: no DMARC record.** Neither `_dmarc.auth.allinonepos.app` nor
`_dmarc.allinonepos.app` resolves. SPF and DKIM alone deliver, but Gmail and
Yahoo treat a missing DMARC policy as a negative signal. Add at Namecheap on the
root domain, TXT, host `_dmarc`:
`v=DMARC1; p=none; rua=mailto:dmarc@allinonepos.app` — start at `p=none`,
watch the reports, tighten to `quarantine` later.

Do not turn off Secure email change to make delivery work. After SMTP and the
templates are live, confirm real delivery and both-inbox completion with a
designated owner. Already-sent emails keep their original layout.
