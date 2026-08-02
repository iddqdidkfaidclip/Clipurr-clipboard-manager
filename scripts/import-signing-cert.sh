#!/usr/bin/env bash
# Import a base64-encoded .p12 into a temporary CI keychain for codesign.
# Expected env:
#   MACOS_CERTIFICATE       — base64 of the .p12
#   MACOS_CERTIFICATE_PWD   — export password for the .p12
#   KEYCHAIN_PASSWORD       — optional; random if unset
set -euo pipefail

if [[ -z "${MACOS_CERTIFICATE:-}" || -z "${MACOS_CERTIFICATE_PWD:-}" ]]; then
  echo "MACOS_CERTIFICATE and MACOS_CERTIFICATE_PWD are required" >&2
  exit 1
fi

KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(openssl rand -base64 32)}"
KEYCHAIN_PATH="$RUNNER_TEMP/clipurr-signing.keychain-db"
CERT_PATH="$RUNNER_TEMP/clipurr-signing.p12"

echo "$MACOS_CERTIFICATE" | base64 --decode > "$CERT_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" \
  -P "$MACOS_CERTIFICATE_PWD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH"
security list-keychain -d user -s "$KEYCHAIN_PATH" $(security list-keychain -d user | sed -e s/\"//g)
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# Self-signed certs are "not trusted" until marked for code signing.
CRT_EXTRACT="$RUNNER_TEMP/clipurr-signing.crt"
openssl pkcs12 -in "$CERT_PATH" -passin "pass:$MACOS_CERTIFICATE_PWD" -nokeys -clcerts -out "$CRT_EXTRACT" 2>/dev/null \
  || openssl pkcs12 -in "$CERT_PATH" -passin "pass:$MACOS_CERTIFICATE_PWD" -nokeys -out "$CRT_EXTRACT"
security add-trusted-cert -d -r trustAsRoot -p codeSign -k "$KEYCHAIN_PATH" "$CRT_EXTRACT" 2>/dev/null || true

# Export the identity name for package-dmg.sh (include untrusted self-signed)
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN_PATH" \
  | sed -n 's/.*"\(Clipurr Release\)".*/\1/p' \
  | head -n 1)"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN_PATH" \
    | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' \
    | head -n 1)"
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN_PATH" \
    | sed -n 's/.*"\(Apple Development: .*\)".*/\1/p' \
    | head -n 1)"
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN_PATH" \
    | sed -n 's/.*"\(.*\)".*/\1/p' \
    | head -n 1)"
fi
if [[ -z "$IDENTITY" ]]; then
  echo "No codesigning identity found in imported keychain" >&2
  security find-identity -p codesigning "$KEYCHAIN_PATH" >&2 || true
  exit 1
fi

echo "CODESIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
echo "Imported signing identity: $IDENTITY"
