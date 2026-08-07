# Version & build numbers (App Store discipline)

Source of truth: [`pubspec.yaml`](../../pubspec.yaml) `version: X.Y.Z+BUILD`

| Field | Maps to | When to bump |
|---|---|---|
| `X.Y.Z` | CFBundleShortVersionString (marketing) | User-visible release (1.0.0 → 1.0.1 after App Review fixes, etc.) |
| `BUILD` | CFBundleVersion | **Every** upload to App Store Connect / TestFlight — must be strictly increasing |

Current store track start: **`1.0.0+2`** (branding / privacy / first IPA candidate).

```bash
# After each successful TestFlight upload, bump build only:
#   1.0.0+2 → 1.0.0+3
# After a public App Store release, bump patch (or minor) and reset narrative:
#   1.0.1+4
```

Do not upload two IPAs with the same `BUILD`.
