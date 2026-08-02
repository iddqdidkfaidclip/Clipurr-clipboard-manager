#!/usr/bin/env bash
# Create a free self-signed "Clipurr Release" code-signing certificate.
# No Apple Developer Program ($99) required — enough for GitHub DMG releases
# so Accessibility TCC sticks across builds.
#
# Usage:
#   ./scripts/create-self-signed-cert.sh
#   ./scripts/create-self-signed-cert.sh --print-secrets   # base64 for GitHub
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CERT_DIR="$ROOT/packaging/signing"
CERT_NAME="Clipurr Release"
COMMON_NAME="Clipurr Release"
P12_PATH="$CERT_DIR/ClipurrRelease.p12"
CRT_PATH="$CERT_DIR/ClipurrRelease.crt"
KEY_PATH="$CERT_DIR/ClipurrRelease.key"
CONF_PATH="$CERT_DIR/ClipurrRelease.cnf"
PASSWORD_PATH="$CERT_DIR/ClipurrRelease.password"

PRINT_SECRETS=0
if [[ "${1:-}" == "--print-secrets" ]]; then
  PRINT_SECRETS=1
fi

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

if [[ -f "$P12_PATH" && -f "$PASSWORD_PATH" ]]; then
  echo "Existing certificate found: $P12_PATH"
else
  echo "==> Creating self-signed code-signing certificate: $CERT_NAME"
  PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
  printf '%s\n' "$PASSWORD" > "$PASSWORD_PATH"
  chmod 600 "$PASSWORD_PATH"

  cat > "$CONF_PATH" <<'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = v3_ext

[req_distinguished_name]
CN = Clipurr Release

[v3_ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

  openssl req -new -x509 -days 3650 -nodes \
    -newkey rsa:2048 \
    -keyout "$KEY_PATH" \
    -out "$CRT_PATH" \
    -config "$CONF_PATH"

  # -legacy helps Keychain import older PKCS#12 encodings on recent OpenSSL.
  openssl pkcs12 -export -legacy \
    -inkey "$KEY_PATH" \
    -in "$CRT_PATH" \
    -out "$P12_PATH" \
    -passout "pass:$PASSWORD" \
    -name "$COMMON_NAME" \
    2>/dev/null \
  || openssl pkcs12 -export \
    -inkey "$KEY_PATH" \
    -in "$CRT_PATH" \
    -out "$P12_PATH" \
    -passout "pass:$PASSWORD" \
    -name "$COMMON_NAME"

  chmod 600 "$P12_PATH" "$KEY_PATH"
  rm -f "$KEY_PATH" "$CONF_PATH"

  LOGIN_KC="$(security login-keychain | sed -e 's/"//g' -e 's/^ *//')"
  security delete-identity -c "$CERT_NAME" "$LOGIN_KC" 2>/dev/null || true
  security import "$P12_PATH" \
    -k "$LOGIN_KC" \
    -P "$PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -T /usr/bin/productsign
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "" \
    "$LOGIN_KC" >/dev/null 2>&1 || true

  # Trust for code signing so local `codesign` accepts the identity.
  # May fail without GUI approval — codesign by name still works for our builds.
  security add-trusted-cert \
    -r trustAsRoot \
    -p codeSign \
    "$CRT_PATH" 2>/dev/null \
  || true

  echo "==> Imported into login keychain as: $CERT_NAME"
fi

PASSWORD="$(cat "$PASSWORD_PATH")"

if ! security find-identity -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
  echo "warning: '$CERT_NAME' not found in keychain." >&2
fi

echo
echo "Certificate ready (kept out of git via packaging/signing/)."
echo "  p12:      $P12_PATH"
echo "  password: $PASSWORD_PATH"

if [[ "$PRINT_SECRETS" -eq 1 ]]; then
  echo
  echo "=== GitHub Actions secrets (paste these) ==="
  echo
  echo "MACOS_CERTIFICATE_PWD:"
  echo "$PASSWORD"
  echo
  echo "MACOS_CERTIFICATE (base64, one line):"
  base64 < "$P12_PATH" | tr -d '\n'
  echo
  echo
  echo "Upload with:"
  echo "  gh secret set MACOS_CERTIFICATE_PWD --body \"$PASSWORD\""
  echo "  gh secret set MACOS_CERTIFICATE < <(base64 < \"$P12_PATH\" | tr -d '\\n')"
fi
