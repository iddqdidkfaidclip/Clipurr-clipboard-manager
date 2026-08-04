#!/usr/bin/env bash
# Sign the latest DMG into docs/appcast.xml for Sparkle.
#
# Env:
#   SPARKLE_PRIVATE_KEY  — EdDSA private key (CI secret), or use Keychain locally
#   GITHUB_REPOSITORY    — owner/repo (default from `gh`)
#   GITHUB_REF_NAME      — tag, e.g. v1.0.2 (required in CI)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep -E '^\s*MARKETING_VERSION:' project.yml | awk '{print $2}' | tr -d '"' || true)"
VERSION="${VERSION:-1.0.5}"
TAG="${GITHUB_REF_NAME:-v${VERSION}}"
DMG="$ROOT/dist/Clipurr-${VERSION}.dmg"
DOCS="$ROOT/docs"
STAGE="$ROOT/dist/appcast-stage"
REPO="${GITHUB_REPOSITORY:-}"

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [[ -z "$REPO" ]]; then
  echo "error: set GITHUB_REPOSITORY or run from a git repo with gh" >&2
  exit 1
fi

if [[ ! -f "$DMG" ]]; then
  echo "error: missing $DMG — run ./scripts/package-dmg.sh first" >&2
  exit 1
fi

SPARKLE_BIN=""
if [[ -n "${SPARKLE_TOOLS_DIR:-}" && -x "${SPARKLE_TOOLS_DIR}/generate_appcast" ]]; then
  SPARKLE_BIN="$SPARKLE_TOOLS_DIR"
else
  for candidate in \
    "$ROOT/.sparkle-tools/bin" \
    /tmp/bin
  do
    if [[ -x "$candidate/generate_appcast" ]]; then
      SPARKLE_BIN="$candidate"
      break
    fi
  done
fi

if [[ -z "$SPARKLE_BIN" ]]; then
  echo "==> Downloading Sparkle tools"
  TOOLS_DIR="$ROOT/.sparkle-tools"
  mkdir -p "$TOOLS_DIR"
  curl -sL -o /tmp/Sparkle-tools.tar.xz \
    "https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz"
  tar -xf /tmp/Sparkle-tools.tar.xz -C "$TOOLS_DIR" bin
  SPARKLE_BIN="$TOOLS_DIR/bin"
fi

rm -rf "$STAGE"
mkdir -p "$STAGE" "$DOCS"
cp "$DMG" "$STAGE/"
if [[ -f "$DOCS/appcast.xml" ]]; then
  cp "$DOCS/appcast.xml" "$STAGE/"
fi

DOWNLOAD_PREFIX="https://github.com/${REPO}/releases/download/${TAG}/"
echo "==> Generating appcast for ${TAG} → ${DOWNLOAD_PREFIX}"

KEY_ARGS=()
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  KEY_FILE="$(mktemp)"
  printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
  KEY_ARGS+=(--ed-key-file "$KEY_FILE")
  trap 'rm -f "$KEY_FILE"' EXIT
elif [[ -f "$ROOT/packaging/signing/sparkle_eddsa_private.key" ]]; then
  KEY_ARGS+=(--ed-key-file "$ROOT/packaging/signing/sparkle_eddsa_private.key")
else
  KEY_ARGS+=(--account clipurr)
fi

"$SPARKLE_BIN/generate_appcast" \
  "${KEY_ARGS[@]}" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  -o "$DOCS/appcast.xml" \
  "$STAGE"

# Older archives without SUPublicEDKey may omit edSignature; sign explicitly.
if ! grep -q 'sparkle:edSignature=' "$DOCS/appcast.xml"; then
  echo "==> Adding EdDSA signature via sign_update"
  SIGN_ARGS=()
  if [[ -n "${KEY_FILE:-}" ]]; then
    SIGN_ARGS+=(--ed-key-file "$KEY_FILE")
  elif [[ -f "$ROOT/packaging/signing/sparkle_eddsa_private.key" ]]; then
    SIGN_ARGS+=(--ed-key-file "$ROOT/packaging/signing/sparkle_eddsa_private.key")
  else
    SIGN_ARGS+=(--account clipurr)
  fi
  SIG_LINE="$("$SPARKLE_BIN/sign_update" "$DMG" "${SIGN_ARGS[@]}")"
  ED_SIG="$(printf '%s' "$SIG_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  if [[ -z "$ED_SIG" ]]; then
    echo "error: sign_update did not return sparkle:edSignature" >&2
    echo "$SIG_LINE" >&2
    exit 1
  fi
  python3 - "$DOCS/appcast.xml" "$ED_SIG" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
sig = sys.argv[2]
text = path.read_text()
needle = 'type="application/octet-stream"/>'
if 'sparkle:edSignature=' in text:
    raise SystemExit(0)
if needle not in text:
    raise SystemExit("enclosure not found in appcast")
replacement = f'sparkle:edSignature="{sig}" type="application/octet-stream"/>'
path.write_text(text.replace(needle, replacement, 1))
PY
fi

# Deltas are optional upload artifacts; keep them next to the DMG for the release.
if compgen -G "$STAGE/*.delta" > /dev/null; then
  cp "$STAGE"/*.delta "$ROOT/dist/" 2>/dev/null || true
fi

echo "==> Wrote $DOCS/appcast.xml"
rm -f "$ROOT/appcast.xml"
