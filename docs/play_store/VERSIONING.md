# Version & build numbers (Play)

Same source of truth as iOS: [`pubspec.yaml`](../../pubspec.yaml) `version: X.Y.Z+BUILD`

| Field | Play | When to bump |
|---|---|---|
| `X.Y.Z` | `versionName` | User-visible release |
| `BUILD` | `versionCode` (integer) | **Every** AAB upload — must strictly increase |

See also [`docs/app_store/VERSIONING.md`](../app_store/VERSIONING.md).

Current track: follow `pubspec.yaml` (e.g. `1.0.0+2`).
