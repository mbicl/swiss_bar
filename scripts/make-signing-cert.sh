#!/bin/bash
# One-time (or rotate-on-demand) setup: generates a self-signed code-signing certificate for
# swiss_bar release builds, imports it into the local login keychain (for local release builds),
# and prints the `gh secret set` commands to upload it for the release GitHub Actions workflow.
#
# We use a self-signed certificate instead of an Apple Developer ID because this project is not
# enrolled in the Apple Developer Program. This does NOT satisfy Gatekeeper/notarization - users
# still see an "unidentified developer" warning (see INSTALL.md) - but it gives every release
# build the same stable code identity, so macOS TCC grants (Accessibility, Input Monitoring)
# survive app updates instead of being reset every release.
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY_NAME="swiss_bar Release Signing"
CERTS_DIR="certs"
P12_PATH="$CERTS_DIR/swiss_bar_signing.p12"

if security find-identity -p codesigning | grep -q "$IDENTITY_NAME"; then
  echo "A '$IDENTITY_NAME' identity already exists in the login keychain."
  echo "Delete it first (Keychain Access, or 'security delete-identity') if you intend to rotate it."
  exit 1
fi

mkdir -p "$CERTS_DIR"

KEY_PATH="$CERTS_DIR/swiss_bar_signing.key.pem"
CERT_PATH="$CERTS_DIR/swiss_bar_signing.cert.pem"
P12_PASSWORD="$(openssl rand -base64 24)"

echo "Generating self-signed code-signing certificate..."
openssl req -x509 -newkey rsa:2048 -keyout "$KEY_PATH" -out "$CERT_PATH" \
  -days 3650 -nodes \
  -subj "/CN=$IDENTITY_NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

echo "Bundling into .p12..."
# -legacy: macOS Keychain Services only understands the old RC2/3DES PKCS#12 encryption:
# modern OpenSSL (3.x) defaults to AES-256+PBKDF2, which `security import` rejects with
# "MAC verification failed" even given the correct password.
openssl pkcs12 -export -legacy \
  -inkey "$KEY_PATH" -in "$CERT_PATH" \
  -out "$P12_PATH" \
  -name "$IDENTITY_NAME" \
  -password "pass:$P12_PASSWORD"

echo "Importing into login keychain for local release builds..."
security import "$P12_PATH" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$P12_PASSWORD" -T /usr/bin/codesign -A
security set-key-partition-list -S apple-tool:,apple: -s \
  -k "" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true

rm -f "$KEY_PATH"

echo
echo "Done. Identity '$IDENTITY_NAME' is now in your login keychain."
echo "After your first release build, check its designated requirement with:"
echo "  codesign -dr - build/swiss_bar.app"
echo "That string must stay identical across releases - it's what macOS TCC pins grants to."
echo
echo "$P12_PATH and the identity are only usable for building; they do not need to be secret to"
echo "an attacker who already has your Mac, but the .p12 IS what CI needs. To let the release"
echo "workflow sign builds, upload it as repo secrets (requires 'gh auth login' once):"
echo
echo "  gh secret set SIGNING_CERT_P12_BASE64 --body \"\$(base64 -i $P12_PATH)\""
echo "  gh secret set SIGNING_CERT_P12_PASSWORD --body \"$P12_PASSWORD\""
echo
echo "Save $P12_PATH and the password above somewhere safe (e.g. a password manager) - if you"
echo "lose them you can re-run this script, but every future release will get a NEW identity,"
echo "which resets Accessibility/Input Monitoring grants for existing users."
