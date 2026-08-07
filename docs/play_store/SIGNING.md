# Android upload signing (Play)

Release builds **must not** use the debug keystore. Gradle loads
`android/key.properties` (gitignored). If that file is missing,
`assembleRelease` / `bundleRelease` fail with a clear error.

## 1. Create upload keystore (once)

```bash
keytool -genkey -v -keystore ~/goldposmm-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias goldposmm_upload
```

Store the `.jks` **outside git** (home directory is fine). Backup offline.
Save store password, key password, and alias in a password manager.

## 2. key.properties

```bash
cp android/key.properties.example android/key.properties
# edit storePassword, keyPassword, keyAlias, storeFile (absolute path)
```

Example:

```properties
storePassword=…
keyPassword=…
keyAlias=goldposmm_upload
storeFile=/Users/YOU/goldposmm-upload.jks
```

Never commit `android/key.properties`, `*.jks`, or `*.keystore`.

## 3. Build AAB

```bash
flutter build appbundle --release --dart-define-from-file=env.local.json
# → build/app/outputs/bundle/release/app-release.aab
```

Optional verify:

```bash
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
```

## 4. Play App Signing

On first upload, accept **Google Play App Signing**. Your `.jks` is the
**upload** key; Google re-signs installs with the app signing key.

If you lose the upload key: Play Console → App signing → request upload key reset.

## 5. Device release without Play

`flutter run --release` also needs `key.properties`. For quick device tests
without a keystore, use `flutter run` (debug) instead.
