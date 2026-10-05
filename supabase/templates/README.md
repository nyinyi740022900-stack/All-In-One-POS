# Bilingual auth email template

`change_email.html` is the production-ready Supabase **Change email address** body, with a single confirmation link and Myanmar/English copy in the same message.

Subject: `All In One POS — အီးမေးလ်ပြောင်းလဲမှု အတည်ပြုရန် / Confirm email change`

Keep `{{ .ConfirmationURL }}`, `{{ .Email }}`, `{{ .NewEmail }}` unchanged. Supabase supplies a separate confirmation URL for each inbox with Secure email change enabled. Never replace the action with a hard-coded native callback; that would skip verification. No secret, actual owner address or live token is stored in the file. It uses inline table layout and system fonts; no JavaScript, external tracking, font/image dependency or unsolicited attachments.

Deploy using Supabase Authentication → Emails → Change email address. Production template editing may require custom SMTP; inspect the current UI before applying. Do not turn off Secure email change to make mail delivery work. Confirm real delivery and both-inbox completion with a designated owner after SMTP/template deployment. Already sent emails retain their original layout.

The app handles `allinonepos://login-callback/` and displays safe invalid/used-link guidance. Clicking a one-time link twice can be rejected; a rejection does not prove the original email change failed. Check the current account email before requesting another change.
