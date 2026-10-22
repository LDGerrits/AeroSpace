#!/usr/bin/env bash
# Creates a self-signed code signing certificate in your login keychain, for build-local-app.sh.
#
# Why: macOS ties the Accessibility permission AeroSpace needs to who signed the app. Signed with the same
# certificate every time, a rebuilt app keeps the permission; signed ad hoc, it loses it on every rebuild.
# (Upstream releases are signed with the maintainer's own certificate, which can't be used here, so the first
# time you switch to a locally built app you grant the permission once more.)
set -euo pipefail

name="${1:-aerospace-local-codesign}"

if security find-certificate -c "$name" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
    echo "Certificate '$name' already exists in the login keychain"
    exit 0
fi

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
password="aerospace-$$"

cat >"$dir/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CONF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/cert.conf" \
    -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$name" \
    -out "$dir/cert.p12" -passout "pass:$password"

# -T lets codesign use the key without asking each time
security import "$dir/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$password" -T /usr/bin/codesign >/dev/null
echo "Created certificate '$name' in the login keychain"
