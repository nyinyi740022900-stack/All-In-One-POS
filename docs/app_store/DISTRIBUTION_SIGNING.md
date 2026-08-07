# Distribution signing (fix IPA export)

## What already works
```text
✓ Built build/ios/archive/Runner.xcarchive
  Version 1.0.0 (2) · Display Name GoldPOSMM · Bundle com.mmpos.mmPos
```

## What failed (2026-08-07 local build)
`flutter build ipa … --export-options-plist=ios/ExportOptions.plist` archived OK, then:

```text
No signing certificate "iOS Distribution" found
Team "Nyi Nyi Khine Nyi Khine" does not have permission to create
  "iOS App Store" provisioning profiles
No profiles for 'com.mmpos.mmPos' were found
```

That means **device Development signing works**, but **App Store distribution is not enabled** for this team yet (membership inactive, wrong role, or free Personal Team).

## Fix (human, Apple Developer portal)

1. Open https://developer.apple.com/account — confirm **Program membership: Active** ($99/yr), not only a free Apple ID team.
2. Certificates, Identifiers & Profiles → **Certificates** → **+** → **Apple Distribution** → CSR from Keychain Access → install `.cer` (creates “Apple Distribution: …” in Keychain).
3. **Identifiers** → ensure App ID `com.mmpos.mmPos` exists.
4. **Profiles** → **+** → App Store → select App ID + Distribution cert → download (or let Xcode Automatic manage after step 2).
5. Xcode → Settings → Accounts → your Apple ID → team `F8KLK8L5SY` → **Download Manual Profiles** / Manage Certificates → ensure Distribution appears.
6. Re-run:
   ```bash
   flutter build ipa --release --dart-define-from-file=env.local.json \
     --export-options-plist=ios/ExportOptions.plist
   ./tool/upload_ios_ipa.sh   # after APP_STORE_CONNECT_* env vars (ACCOUNT.md)
   ```
7. Or open the existing archive and export from Organizer:
   ```bash
   open build/ios/archive/Runner.xcarchive
   ```
   Distribute App → App Store Connect → Upload.

## App Store Connect API (upload)
Still required for `tool/upload_ios_ipa.sh` — see [ACCOUNT.md](ACCOUNT.md).

## Icons
Flutter validated the archive but warned the **App Icon / Launch Image look like placeholders**. Replace marketing artwork in `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (and Android mipmaps) with final GoldPOSMM branding before public submit — 1024×1024 must not be the default Flutter logo.
