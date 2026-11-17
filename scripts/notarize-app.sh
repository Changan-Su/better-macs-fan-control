#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
architecture="${1:?architecture required}"
case "$architecture" in arm64|x86_64) ;; *) exit 1;; esac
app="dist/macos-$architecture/Better Fan.app"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app" "$work/BetterFan.zip"
xcrun notarytool submit "$work/BetterFan.zip" --key "$NOTARY_KEY_PATH" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
