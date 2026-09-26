#!/usr/bin/env bash
#
# Builds an unsigned .ipa locally — the same steps as .github/workflows/build.yml,
# so a green CI run and a local run can never drift apart.
#
# Usage:
#   ./scripts/build-ipa.sh              # includes the ~2 GB offline model
#   WITH_MODEL=0 ./scripts/build-ipa.sh # online-AI-only build (no download, fast)
#
# Needs: macOS with Xcode 16.3+ (swift-llama-cpp requires the Swift 6.1 toolchain),
# and Homebrew's xcodegen. Signing is intentionally disabled — see the IPA notes below.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

WITH_MODEL="${WITH_MODEL:-1}"
BUILD_DIR="${BUILD_DIR:-build}"
APP_NAME="Sahand Info"          # PRODUCT_NAME from project.yml — the .app keeps this name
SCHEME="${SCHEME:-SahandInfo}"
CONFIGURATION="${CONFIGURATION:-Release}"

command -v xcodegen >/dev/null 2>&1 || {
  echo "error: xcodegen not found — install it with: brew install xcodegen" >&2
  exit 1
}

if [[ "$WITH_MODEL" == "1" ]]; then
  "$REPO_ROOT/scripts/fetch-model.sh"
else
  echo "· skipping the offline model (WITH_MODEL=0) — Offline AI will report a missing model"
  mkdir -p Resources            # project.yml lists Resources as a source folder
fi

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
echo "Apple ID using AltStore or Sideloadly, or rebuild here after setting a real"
echo "DEVELOPMENT_TEAM / CODE_SIGN_IDENTITY in project.yml."
