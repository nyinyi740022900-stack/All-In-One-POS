# Play Console — account & app

## Package name (locked on first upload)

| Item | Value |
|---|---|
| Application ID | `com.mmpos.mm_pos` |
| Display name | GoldPOSMM |
| Do not change | Application ID after first Play upload |

## Phase 0 checklist

1. Open [Google Play Console](https://play.google.com/console) and complete **developer account** registration ($25 one-time) if needed.
2. **Create app** → GoldPOSMM → default language English (U.S.) → App → Free.
3. Complete the required declarations (privacy policy, export compliance, etc.) as prompted.
4. Confirm the app will use package **`com.mmpos.mm_pos`** (must match [`android/app/build.gradle.kts`](../../android/app/build.gradle.kts)).
5. Enable **Play App Signing** when first prompted (recommended default — Google holds the app signing key; you keep the **upload** key).

## Done when

- [ ] Developer account Active
- [ ] App record created
- [ ] Upload keystore created + `android/key.properties` filled ([SIGNING.md](SIGNING.md))
- [ ] First AAB on Internal testing track
