#!/bin/bash
# Creates the self-signed code signing certificate "AutoHush Self-Signed"
# (valid 10 years) and imports it into the login keychain. Run it once.
#
# Why: macOS keeps privacy permissions (Automation, System Audio Recording) for
# an app identified by its signing certificate. Ad-hoc builds are identified by
# their content hash, so every build or update would need the permissions again.
# The certificate does not make Gatekeeper trust the app; that needs Apple's
# paid Developer ID.
#
# Sign every release with the same certificate, or users lose their permissions
# on update: back it up (see the end of this script's output).
#
# Usage: bash Scripts/create-signing-certificate.sh
# Environment: SIGNING_KEYCHAIN to import into another keychain (default: login).
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

KEYCHAIN="${SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
if SIGNING_KEYCHAIN="$KEYCHAIN" has_identity "$SELF_SIGNED_IDENTITY"; then
    echo "\"$SELF_SIGNED_IDENTITY\" already exists in $KEYCHAIN; nothing to do."
    exit 0
fi
command -v openssl >/dev/null || fail "openssl not found"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $SELF_SIGNED_IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

step "Creating certificate \"$SELF_SIGNED_IDENTITY\""
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# macOS cannot import OpenSSL 3's default PKCS#12 encryption; use the legacy one.
TRANSFER_PASSWORD="$(uuidgen)"
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$SELF_SIGNED_IDENTITY" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout "pass:$TRANSFER_PASSWORD" -out "$WORK/identity.p12"

step "Importing into $KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$TRANSFER_PASSWORD" -T /usr/bin/codesign >/dev/null
SIGNING_KEYCHAIN="$KEYCHAIN" has_identity "$SELF_SIGNED_IDENTITY" || fail "import did not produce a signing identity"

echo ""
echo "Done. Builds are now signed with \"$SELF_SIGNED_IDENTITY\"."
echo "The first build may ask to let codesign use the key: choose Always Allow."
echo ""
echo "Back it up now: Keychain Access → login → My Certificates → right-click"
echo "\"$SELF_SIGNED_IDENTITY\" → Export… → save the .p12 with a password somewhere safe."
echo "Without it, future releases cannot keep users' permissions."
