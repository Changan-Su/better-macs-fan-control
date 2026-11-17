#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
architecture="${1:-$(uname -m)}"
case "$architecture" in arm64|x86_64) ;; *) echo 'Expected arm64 or x86_64' >&2; exit 1;; esac
configuration="${CONFIGURATION:-release}"
export MACOSX_DEPLOYMENT_TARGET=13.0
node scripts/build-ui.mjs
swift build -c "$configuration" --arch "$architecture" --scratch-path ".build/$architecture"
bin_path="$(swift build -c "$configuration" --arch "$architecture" --scratch-path ".build/$architecture" --show-bin-path)"
app="dist/macos-$architecture/Better Fan.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Library/LaunchDaemons" "$app/Contents/Library/HelperTools"
cp "$bin_path/BetterFan" "$app/Contents/MacOS/BetterFan"
cp "$bin_path/BetterFanHelper" "$app/Contents/Library/HelperTools/BetterFanHelper"
cp "$bin_path/BetterFanProbe" "$app/Contents/MacOS/BetterFanProbe"
cp dist/native/index.html "$app/Contents/Resources/index.html"
cp third-party/Stats-LICENSE.txt "$app/Contents/Resources/Stats-LICENSE.txt"
cp packaging/com.changansu.BetterFan.Helper.plist "$app/Contents/Library/LaunchDaemons/"
APP_PATH="$app" python3 - <<'PY'
import json,os,plistlib
from pathlib import Path
package=json.loads(Path('package.json').read_text())
p=Path(os.environ['APP_PATH'])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.changansu.BetterFan','CFBundleName':'Better Fan','CFBundleDisplayName':'Better Fan','CFBundleExecutable':'BetterFan','CFBundlePackageType':'APPL','CFBundleShortVersionString':os.environ.get('APP_VERSION',package['version']).split('-',1)[0],'CFBundleVersion':os.environ.get('BUILD_NUMBER','1'),'LSMinimumSystemVersion':'13.0','CFBundleIconFile':'AppIcon','NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication'}))
PY
if [ ! -f dist/AppIcon.icns ]; then
  swift scripts/icon.swift dist/AppIcon.iconset
  iconutil -c icns dist/AppIcon.iconset -o dist/AppIcon.icns
fi
cp dist/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
identity="${SIGN_IDENTITY:--}"
if [ "$identity" = '-' ]; then sign_args=(--timestamp=none); else sign_args=(--options runtime --timestamp); fi
codesign --force --sign "$identity" "${sign_args[@]}" --identifier com.changansu.BetterFan.Helper "$app/Contents/Library/HelperTools/BetterFanHelper"
codesign --force --sign "$identity" "${sign_args[@]}" --identifier com.changansu.BetterFan.Probe "$app/Contents/MacOS/BetterFanProbe"
codesign --force --sign "$identity" "${sign_args[@]}" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
plutil -lint "$app/Contents/Info.plist" "$app/Contents/Library/LaunchDaemons/com.changansu.BetterFan.Helper.plist"
echo "Built $app"
