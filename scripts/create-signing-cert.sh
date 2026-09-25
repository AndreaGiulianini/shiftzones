#!/usr/bin/env bash
# Creates a self-signed "ShiftZones Local Signing" certificate in the login keychain.
# Only needed for development: with a stable signature the Accessibility permission survives rebuilds.
# macOS asks for your password to trust the certificate for code signing.
set -euo pipefail

NAME="ShiftZones Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "✓ The \"$NAME\" certificate already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/cert.p12" -passout pass:shiftzones
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P shiftzones -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo "✓ Certificate \"$NAME\" created. Now rebuild with scripts/build.sh"
echo "  and grant the Accessibility permission one last time."
