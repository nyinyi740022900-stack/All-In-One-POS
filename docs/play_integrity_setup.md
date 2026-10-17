# Play Integrity — setup and rollout

Code shipped 2026-10-17 (`supabase/functions/_shared/play_integrity.ts`,
`activate` → `attestCall`, `lib/core/integrity/play_integrity.dart`,
`MainActivity.kt` `integrityToken`, migration `0106_integrity_checks.sql`).
It does nothing useful until the steps below are done, and blocks nothing
until step 6.

## What it checks

Android calls to `activate` that grant a trial or a Premium receipt —
`start_trial`, `refresh_account_license`, `resync_session`, `switch_branch` —
carry a Play Integrity token bound to the action, device and a one-time
nonce. The server decodes it with Google and records a verdict in
`integrity_checks`:

| Verdict | Meaning | Blocked when enforcing? |
|---|---|---|
| `pass` | Installed from Play, our app | no |
| `pass_sideload` | Our upload-key APK (GitHub), not from Play | no |
| `fail` | Re-signed, wrong package/request, stale token, replayed nonce | **yes** |
| `unavailable` | Phone gave no token (no Play services, Huawei…) | no (owner call) |
| `missing` | Build ≥ 9 sent nothing at all | yes |
| `not_configured` | Server has no Google credentials | no |
| `error` | Google API / our failure | no |
| `not_android` | Client says iOS / web / desktop | no |

Device integrity (root checks) is recorded, never required.

## Owner setup (once)

1. **Play Console → Test and release → App integrity → Play Integrity API →
   Link a Cloud project.** Link the Google Cloud project that already holds
   the app's Google sign-in OAuth clients (or create one). This enables the
   Play Integrity API on it.
2. **Google Cloud console → that project → IAM & Admin → Service accounts →
   Create service account** `play-integrity-verifier`. No roles are needed —
   being in the linked project is what lets it decode tokens.
3. That service account → **Keys → Add key → JSON**. Keep the file private;
   never commit it.
4. Store it as a Supabase secret (run in the repo, then delete the file):
   ```bash
   supabase secrets set --project-ref gnikispsurwrmkspuisj PLAY_INTEGRITY_SA_JSON="$(cat ~/Downloads/<key-file>.json)"
   ```
5. **Cloud project NUMBER** (not the ID — Cloud console → Dashboard → Project
   info). It is public, not a secret. Add it to `env.local.json` as
   `"PLAY_INTEGRITY_CLOUD_PROJECT": "<number>"` and to the GitHub Actions
   secrets as `PLAY_INTEGRITY_CLOUD_PROJECT`, then build the next release
   (build ≥ 9). Without it the app reports `not_configured`.

## Deploy order

```bash
supabase db push                                   # 0106_integrity_checks.sql
supabase functions deploy activate --project-ref gnikispsurwrmkspuisj
supabase functions deploy admin --project-ref gnikispsurwrmkspuisj
./tool/build_web.sh admin                          # then §3 of the deploy skill
```

The function tolerates the table not existing yet (the insert error is
ignored and the call proceeds), so the order is not load-bearing.

## Rollout

6. Watch **Admin → Storage → App integrity (last 7 days)** through the closed
   beta. When real shops show `pass` / `pass_sideload` and the only `fail`s
   are copies you recognise as modified, set **Config →
   `integrity.android_mode` = `enforce`**. Back to `monitor` instantly
   undoes it — no app release either way.

## Known limits (read before enforcing)

- A client can **claim** to be iOS or web and skip the Android check. Closing
  that needs iOS App Attest (follow-up) and keeping web out of receipt calls.
- It protects what the **server** hands out. A patched app that never calls
  the server can still unlock phone-only Premium screens; the client
  signature check and obfuscation are what slow that down.
- Builds before 9 send nothing and are never blocked, so enforcement only
  bites once old builds are gone (consider a minimum-version gate then).
- `integrity_checks` grows with every gated call; prune it if it gets large.
