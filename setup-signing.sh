#!/bin/bash
# One-time: create a self-signed code-signing identity in a dedicated keychain.
# Signing with a STABLE identity gives the app a stable code-signing designated
# requirement, so macOS TCC keeps the Accessibility / Input Monitoring grants
# across rebuilds (ad-hoc signing changes the hash every build and drops them).
# The keychain has a known local password so build-app.sh can sign non-interactively.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIR="$ROOT/.signing"
KC="$DIR/lexicon-signing.keychain-db"
KCPW="lexicon-signing"   # local dev keychain password (not a secret)
P12PW="lexicon"
IDENTITY="Lexicon Dev"

mkdir -p "$DIR"

cat > "$DIR/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Lexicon Dev
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "==> generating self-signed code-signing cert"
openssl req -x509 -newkey rsa:2048 -keyout "$DIR/key.pem" -out "$DIR/cert.pem" \
  -days 3650 -nodes -config "$DIR/cert.cnf" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -out "$DIR/identity.p12" \
  -passout "pass:$P12PW" -name "$IDENTITY" \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES >/dev/null 2>&1

echo "==> creating signing keychain"
rm -f "$KC"
security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings "$KC"            # no auto-lock
security unlock-keychain -p "$KCPW" "$KC"
security import "$DIR/identity.p12" -k "$KC" -P "$P12PW" -T /usr/bin/codesign -A >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" >/dev/null 2>&1

echo "==> identity in keychain:"
security find-identity "$KC" | grep "$IDENTITY" || { echo "ERROR: identity not found"; exit 1; }
echo "Done. build-app.sh will now sign with \"$IDENTITY\"."
