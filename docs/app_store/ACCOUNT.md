# App Store Connect — account & app record

## Verified on this machine (2026-08-07)

| Item | Value | Status |
|---|---|---|
| Development Team ID | `F8KLK8L5SY` | Present in Xcode project |
| Bundle ID | `com.mmpos.mmPos` | Do **not** change (sideload installs) |
| Signing identity | Apple Development: `nyinyi1451996@icloud.com` (`MU3QKXW37H`) | Valid for device installs |
| App Store Connect API key | — | **Not on disk** — create before upload (below) |

## Phase 0 checklist (human, once)

1. Confirm [Apple Developer Program](https://developer.apple.com/account) membership is **Active** for team `F8KLK8L5SY`.
2. Open [App Store Connect](https://appstoreconnect.apple.com) → **My Apps** → **+** → **New App**:
   - Platform: iOS
   - Name: **GoldPOSMM** (or available variant)
   - Primary language: English (U.S.) — add Myanmar localization later
   - Bundle ID: select **`com.mmpos.mmPos`** (register under Certificates, Identifiers & Profiles if missing)
   - SKU: `goldposmm-ios` (immutable internal id)
   - User Access: Full Access
3. Under **Users and Access → Integrations → App Store Connect API**, create a key:
   - Role: **Admin** or **App Manager**
   - Download the `.p8` once → store outside git as:
     `~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8`
   - Note **Issuer ID** and **Key ID**
4. Export for CLI (add to shell profile or a local untracked file — never commit):

```bash
export APP_STORE_CONNECT_KEY_ID=XXXXXXXXXX
export APP_STORE_CONNECT_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export APP_STORE_CONNECT_KEY_PATH=$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

5. Re-run upload: see [../.claude/skills/deploy/SKILL.md](../../.claude/skills/deploy/SKILL.md) §5 (TestFlight IPA).

## Register Bundle ID (if Connect cannot see it)

Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs → App:

- Description: GoldPOSMM
- Bundle ID: Explicit `com.mmpos.mmPos`
- Capabilities: none required beyond defaults (no Push/Associated Domains yet)

## Done when

- [x] Team + bundle verified in repo / local signing
- [x] Release **archive** built (`build/ios/archive/Runner.xcarchive`, 1.0.0+2)
- [ ] **Apple Distribution** certificate + App Store profile (see [DISTRIBUTION_SIGNING.md](DISTRIBUTION_SIGNING.md))
- [ ] App record exists in App Store Connect
- [ ] API key installed for `tool/upload_ios_ipa.sh`
- [ ] IPA export + TestFlight upload succeeds
