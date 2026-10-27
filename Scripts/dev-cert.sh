#!/bin/bash
# Creates (once) a self-signed code-signing certificate in a dedicated keychain and prints its name.
#
# Why: macOS ties privacy permissions (Screen Recording) to the app's code identity. An ad-hoc
# signature's identity is the binary's hash, so every rebuild is a "new app" and the user is asked
# again. A certificate, even self-signed, gives a stable identity: "identifier + certificate leaf".
# This does not satisfy Gatekeeper (that needs a Developer ID), it only keeps permissions stable.
#
# Everything lives in ~/Library/Keychains/screenjot-dev.keychain-db plus one entry in your
# certificate trust settings. macOS may ask for your login password once, for the trust step.
# Undo: security delete-keychain ~/Library/Keychains/screenjot-dev.keychain-db
set -euo pipefail

NAME="ScreenJot Dev Signing"
KEYCHAIN="$HOME/Library/Keychains/screenjot-dev.keychain-db"
KEYCHAIN_PASSWORD="screenjot-dev"

valid() { security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$NAME\""; }

if valid; then
    echo "$NAME"
    exit 0
fi

# A keychain without a *valid* identity (earlier script version, or a failed trust step)
# is thrown away so we never accumulate duplicates.
if [ -f "$KEYCHAIN" ]; then
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || rm -f "$KEYCHAIN"
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

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"   # never auto-lock
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P p12pass -T /usr/bin/codesign -T /usr/bin/security >/dev/null
# Let codesign use the key without a GUI prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# Make the keychain visible to codesign's default search path.
CURRENT=$(security list-keychains -d user | tr -d '"' | xargs)
case "$CURRENT" in *screenjot-dev.keychain-db*) ;; *) security list-keychains -d user -s $CURRENT "$KEYCHAIN" ;; esac

# A self-signed certificate is "not trusted" until we say so; codesign refuses untrusted identities.
echo "Trusting the certificate for code signing (macOS may ask for your login password)…" >&2
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if valid; then
    echo "$NAME"
else
    echo "Certificate created but still not trusted; falling back to ad-hoc signing." >&2
    echo "-"
fi
