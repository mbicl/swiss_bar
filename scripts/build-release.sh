#!/bin/bash
# Builds, signs, and packages a swiss_bar release. Used both locally and by
# .github/workflows/release.yml - the signing identity must already be in the active keychain
# (see scripts/make-signing-cert.sh for local setup; the release workflow imports the identity
# from the SIGNING_CERT_P12_BASE64/SIGNING_CERT_P12_PASSWORD secrets into a temp keychain).
#
# Usage: scripts/build-release.sh <version>   e.g. scripts/build-release.sh 1.0.0
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: build-release.sh <version>, e.g. 1.0.0}"
IDENTITY="${SIGNING_IDENTITY:-swiss_bar Release Signing}"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-$(git rev-list --count HEAD)}"

BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/swiss_bar.app"

if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
  echo "error: signing identity '$IDENTITY' not found in the active keychain." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building swiss_bar $VERSION (build $BUILD_NUMBER), unsigned"
xcodebuild -project swiss_bar.xcodeproj -scheme swiss_bar -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> Signing with '$IDENTITY'"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP_PATH"

echo "==> Verifying signature"
codesign --verify --strict -vv "$APP_PATH"
echo "Designated requirement (must stay identical release to release for TCC grants to survive):"
codesign -dr - "$APP_PATH"

echo "==> Packaging DMG"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG_PATH="$BUILD_DIR/swiss_bar-$VERSION.dmg"
hdiutil create -volname "swiss_bar $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"

echo "==> Packaging zip"
ZIP_PATH="$BUILD_DIR/swiss_bar-$VERSION.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo
echo "Built:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
