#!/bin/bash
# Creates (once) a self-signed code-signing certificate in a dedicated keychain and prints its name.
#
# Why: macOS ties privacy permissions (Screen Recording) to the app's code identity. An ad-hoc
# signature's identity is the binary's hash, so every rebuild is a "new app" and the user is asked
# again. A certificate, even self-signed, gives a stable identity: "identifier + certificate leaf".
# This does not satisfy Gatekeeper (that needs a Developer ID), it only keeps permissions stable.
#
# Everything lives in ~/Library/Keychains/screenjot-dev.keychain-db; delete that file to undo.
set -euo pipefail

NAME="ScreenJot Dev Signing"
KEYCHAIN="$HOME/Library/Keychains/screenjot-dev.keychain-db"
KEYCHAIN_PASSWORD="screenjot-dev"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$NAME"; then
    echo "$NAME"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
O = ScreenJot
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf" >/dev/null 2>&1
# -legacy keeps the p12 importable by the system Security framework on newer OpenSSL builds.
openssl pkcs12 -export -legacy -out "$WORK/cert.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -passout pass:p12pass >/dev/null 2>&1 \
 || openssl pkcs12 -export -out "$WORK/cert.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -passout pass:p12pass >/dev/null 2>&1

if [ ! -f "$KEYCHAIN" ]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"   # never auto-lock
fi
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P p12pass -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# Let codesign use the key without a GUI prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# Make the keychain visible to codesign's default search path.
CURRENT=$(security list-keychains -d user | tr -d '"' | xargs)
case "$CURRENT" in *screenjot-dev.keychain-db*) ;; *) security list-keychains -d user -s $CURRENT "$KEYCHAIN" ;; esac

echo "$NAME"
