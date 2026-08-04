#!/usr/bin/env bash
# Build a Release Clipurr.app and wrap it in a styled DMG.
#
# Signing (free self-signed is enough — no $99 Apple Developer needed):
#   CODESIGN_IDENTITY     — e.g. "Clipurr Release" or Developer ID…
#   MACOS_CERTIFICATE*    — imported in CI via import-signing-cert.sh
#
# Optional notarization (requires paid Apple Developer Program):
#   APPLE_ID / APPLE_APP_PASSWORD / APPLE_TEAM_ID
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BG="$ROOT/packaging/dmg/background.png"
DIST="$ROOT/dist"
DERIVED="$ROOT/DerivedData"
APP="$DERIVED/Build/Products/Release/Clipurr.app"
ENTITLEMENTS="$ROOT/Clipurr/Clipurr.entitlements"

# Background is 1024×712. Dashed frames center at ~(250,486) and ~(769,486).
# Icons sit slightly above frame centers so labels clear the bottom dashed line.
WINDOW_WIDTH=1024
WINDOW_HEIGHT=712
ICON_SIZE=128
APP_ICON_X=250
APP_ICON_Y=466
APPS_ICON_X=769
APPS_ICON_Y=466

if [[ ! -f "$BG" ]]; then
  echo "Missing DMG background: $BG" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg not found. Install with: brew install create-dmg" >&2
  exit 1
fi

VERSION="$(grep -E '^\s*MARKETING_VERSION:' project.yml | awk '{print $2}' | tr -d '"' || true)"
VERSION="${VERSION:-1.0.5}"

resolve_codesign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CODESIGN_IDENTITY"
    return
  fi
  local identity=""
  # Include untrusted identities (-v would hide self-signed until Always Trust).
  # Prefer stable self-signed release cert (free) for GitHub DMGs.
  identity="$(security find-identity -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Clipurr Release\)".*/\1/p' \
    | head -n 1 || true)"
  if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p' \
      | head -n 1 || true)"
  fi
  if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development: .*\)".*/\1/p' \
      | head -n 1 || true)"
  fi
  printf '%s\n' "$identity"
}

is_apple_distribution_identity() {
  [[ "$1" == Developer\ ID\ Application:* ]]
}

sign_app() {
  local identity="$1"
  echo "==> Codesigning with: $identity"

  local timestamp_args=(--timestamp=none)
  if is_apple_distribution_identity "$identity"; then
    timestamp_args=(--timestamp)
  fi

  # Never use --deep: it can leave Sparkle nested helpers with the original
  # Team ID / wrong entitlements, and dyld then aborts at launch. Sign inside-out.
  local sparkle="$APP/Contents/Frameworks/Sparkle.framework"
  local sparkle_b="$sparkle/Versions/B"
  if [[ -d "$sparkle_b" ]]; then
    codesign --force "${timestamp_args[@]}" --options runtime \
      --sign "$identity" "$sparkle_b/XPCServices/Installer.xpc"
    # Downloader ships its own entitlements; preserve them.
    codesign --force "${timestamp_args[@]}" --options runtime \
      --preserve-metadata=entitlements \
      --sign "$identity" "$sparkle_b/XPCServices/Downloader.xpc"
    codesign --force "${timestamp_args[@]}" --options runtime \
      --sign "$identity" "$sparkle_b/Autoupdate"
    codesign --force "${timestamp_args[@]}" --options runtime \
      --sign "$identity" "$sparkle_b/Updater.app"
    codesign --force "${timestamp_args[@]}" --options runtime \
      --sign "$identity" "$sparkle_b/Sparkle"
    codesign --force "${timestamp_args[@]}" --options runtime \
      --sign "$identity" "$sparkle"
  fi

  codesign \
    --force \
    "${timestamp_args[@]}" \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$identity" \
    "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
}

notarize_dmg() {
  local dmg_path="$1"
  local identity="$2"
  if ! is_apple_distribution_identity "$identity"; then
    echo "==> Skipping notarization (self-signed / non–Developer ID build)"
    return
  fi
  if [[ -z "${APPLE_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" || -z "${APPLE_TEAM_ID:-}" ]]; then
    echo "==> Skipping notarization (APPLE_ID / APPLE_APP_PASSWORD / APPLE_TEAM_ID not set)"
    return
  fi
  echo "==> Submitting DMG for notarization"
  xcrun notarytool submit "$dmg_path" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  xcrun stapler staple "$dmg_path"
  echo "==> Notarization complete"
}

BUILD_SETTINGS=()
SIGN_IDENTITY="$(resolve_codesign_identity)"

if [[ -n "${CI:-}" && -z "$SIGN_IDENTITY" ]]; then
  echo "error: CI release builds need a stable signing cert so Accessibility works." >&2
  echo "Free option (no Apple Developer \$99):" >&2
  echo "  1) ./scripts/create-self-signed-cert.sh --print-secrets" >&2
  echo "  2) gh secret set MACOS_CERTIFICATE / MACOS_CERTIFICATE_PWD" >&2
  exit 1
fi

if [[ -n "${CI:-}" ]]; then
  # Identity comes from the imported keychain certificate; don't let Xcode
  # Automatic signing fight the CI keychain.
  BUILD_SETTINGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
  )
fi

echo "==> Building Release Clipurr ${VERSION}"
xcodebuild \
  -scheme Clipurr \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  build \
  "${BUILD_SETTINGS[@]+"${BUILD_SETTINGS[@]}"}" \
  | tail -20

if [[ ! -d "$APP" ]]; then
  echo "Release app missing at $APP" >&2
  exit 1
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  sign_app "$SIGN_IDENTITY"
else
  echo "==> Warning: no codesign identity — run ./scripts/create-self-signed-cert.sh" >&2
  echo "    Unsigned DMGs break Accessibility for downloaded installs." >&2
fi

mkdir -p "$DIST"
DMG="$DIST/Clipurr-${VERSION}.dmg"
STAGE="$DIST/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"

echo "==> Creating DMG → $DMG"
# create-dmg may leave a temporary RW image if Finder AppleScript flakes;
# still produce a usable final image on success.
create-dmg \
  --volname "Clipurr" \
  --background "$BG" \
  --window-pos 200 120 \
  --window-size "$WINDOW_WIDTH" "$WINDOW_HEIGHT" \
  --icon-size "$ICON_SIZE" \
  --icon "Clipurr.app" "$APP_ICON_X" "$APP_ICON_Y" \
  --app-drop-link "$APPS_ICON_X" "$APPS_ICON_Y" \
  --no-internet-enable \
  --overwrite \
  "$DMG" \
  "$STAGE"

rm -rf "$STAGE"

if [[ -n "$SIGN_IDENTITY" ]]; then
  notarize_dmg "$DMG" "$SIGN_IDENTITY"
fi

echo "==> Done: $DMG"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E '^(Authority|TeamIdentifier|Signature|Identifier)=' || true

if [[ -z "${CI:-}" ]]; then
  open -R "$DMG"
fi
