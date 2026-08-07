#!/usr/bin/env bash
# Upload a Release IPA to App Store Connect (TestFlight).
# Requires: APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID,
#           APP_STORE_CONNECT_KEY_PATH (path to AuthKey_*.p8)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPA="${1:-$ROOT/build/ios/ipa/*.ipa}"
# shellcheck disable=SC2086
IPA_FILE=$(ls -1 $IPA 2>/dev/null | head -1 || true)
if [[ -z "${IPA_FILE:-}" || ! -f "$IPA_FILE" ]]; then
  echo "IPA not found. Build first:"
  echo "  flutter build ipa --release --dart-define-from-file=env.local.json \\"
  echo "    --export-options-plist=ios/ExportOptions.plist"
  exit 1
fi
: "${APP_STORE_CONNECT_KEY_ID:?set APP_STORE_CONNECT_KEY_ID}"
: "${APP_STORE_CONNECT_ISSUER_ID:?set APP_STORE_CONNECT_ISSUER_ID}"
: "${APP_STORE_CONNECT_KEY_PATH:?set APP_STORE_CONNECT_KEY_PATH}"
if [[ ! -f "$APP_STORE_CONNECT_KEY_PATH" ]]; then
  echo "Missing API key file: $APP_STORE_CONNECT_KEY_PATH"
  exit 1
fi
echo "Uploading $IPA_FILE …"
xcrun altool --upload-app --type ios \
  --file "$IPA_FILE" \
  --apiKey "$APP_STORE_CONNECT_KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
echo "Done. Process the build in App Store Connect → TestFlight (often 5–20 min)."
