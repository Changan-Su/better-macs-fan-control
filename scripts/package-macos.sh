#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
architecture="${1:-$(uname -m)}"
case "$architecture" in arm64|x86_64) ;; *) exit 1;; esac
version="${APP_VERSION:-$(node -p "require('./package.json').version")}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]] || { echo 'Invalid version'; exit 1; }
app="dist/macos-$architecture/Better Fan.app"
[ -d "$app" ] || { echo 'Build the app first'; exit 1; }
suffix=''; if [ "${SIGNED_BUILD:-false}" != true ]; then suffix='-unsigned-monitor'; fi
name="BetterFan-$version-macos-$architecture$suffix"
mkdir -p dist/packages
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Better Fan.app"
ln -s /Applications "$stage/Applications"
cp packaging/INSTALL.zh-CN.md "$stage/安装说明.md"
hdiutil create -volname 'Better Fan' -srcfolder "$stage" -ov -format UDZO "dist/packages/$name.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/packages/$name.zip"
(cd dist/packages && shasum -a 256 "$name.dmg" "$name.zip" > "$name.sha256")
