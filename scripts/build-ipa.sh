#!/usr/bin/env bash
#
# Builds an unsigned .ipa locally — the same steps as .github/workflows/build.yml,
# so a green CI run and a local run can never drift apart.
#
# Usage:
#   ./scripts/build-ipa.sh
#
# Needs: macOS with Xcode 15 or newer (anything with the iOS 17 SDK) and Homebrew's
# xcodegen. There are no package dependencies to resolve, so the first build is quick.
# Signing is intentionally left off — see the note printed at the end.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="${BUILD_DIR:-build}"
APP_NAME="Sahand Info"          # PRODUCT_NAME from project.yml — the .app keeps this name
SCHEME="${SCHEME:-SahandInfo}"
CONFIGURATION="${CONFIGURATION:-Release}"

command -v xcodegen >/dev/null 2>&1 || {
  echo "error: xcodegen not found — install it with: brew install xcodegen" >&2
  exit 1
}

echo "→ xcodegen generate"
xcodegen generate

echo "→ xcodebuild $SCHEME ($CONFIGURATION, iphoneos)"
xcodebuild -project "SahandInfo.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$BUILD_DIR/Build/Products/${CONFIGURATION}-iphoneos/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || { echo "error: expected built app at $APP_PATH" >&2; exit 1; }

echo "→ packaging SahandInfo.ipa"
rm -rf Payload SahandInfo.ipa
mkdir -p Payload
cp -R "$APP_PATH" Payload/
zip -qry SahandInfo.ipa Payload
rm -rf Payload

echo
echo "✓ SahandInfo.ipa ready ($(du -h SahandInfo.ipa | cut -f1))"
echo
echo "It is UNSIGNED, like the CI artifact. To get it onto a phone, re-sign it with your own"
echo "Apple ID using AltStore or Sideloadly, drop it on LiveContainer (which runs unsigned"
echo "builds as-is), or set a real DEVELOPMENT_TEAM / CODE_SIGN_IDENTITY in project.yml and"
echo "archive from Xcode."
