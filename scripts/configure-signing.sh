#!/bin/bash
set -euo pipefail
# Runs on an ephemeral macOS runner. A partially configured release must fail.
required=(APPLE_CERTIFICATE_P12 APPLE_CERTIFICATE_PASSWORD APPLE_NOTARY_KEY APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER)
configured=0
for name in "${required[@]}"; do
  [[ -z "${!name:-}" ]] || configured=$((configured+1))
done
if [[ "$configured" == 0 ]]; then
  echo 'SIGNED_BUILD=false' >> "$GITHUB_ENV"
  echo '::notice::No Apple signing credentials configured. Building a monitoring preview.'
  exit 0
fi
[[ "$configured" == "${#required[@]}" ]] || { echo '::error::Configure all five Apple signing secrets.'; exit 1; }
work="$RUNNER_TEMP/betterfan-signing"
mkdir -p "$work"
chmod 700 "$work"
p12="$work/signing.p12"
notary_key="$work/notary.p8"
printf '%s' "$APPLE_CERTIFICATE_P12" | base64 -D > "$p12"
printf '%s' "$APPLE_NOTARY_KEY" | base64 -D > "$notary_key"
chmod 600 "$notary_key"
keychain="$work/codesign.keychain-db"
password="$(openssl rand -hex 24)"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$p12" -k "$keychain" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
rm -f "$p12"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
# Include system-provided intermediates while making the temporary private key available.
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
identity="$(security find-identity -v -p codesigning "$keychain" | awk '/Developer ID Application/ { print $2; exit }')"
[[ "$identity" =~ ^[A-Fa-f0-9]{40}$ ]] || { echo '::error::No valid Developer ID Application certificate in configured P12.'; exit 1; }
{
  echo 'SIGNED_BUILD=true'
  echo "SIGN_IDENTITY=$identity"
  echo "NOTARY_KEY_PATH=$notary_key"
} >> "$GITHUB_ENV"
