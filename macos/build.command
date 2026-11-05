#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/DAAK Duffy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun --sdk macosx swiftc -parse-as-library -O \
  -target "$(uname -m)-apple-macos13.0" \
  -o "$APP/Contents/MacOS/daakDuffy" \
  "$ROOT"/Sources/*.swift \
  -framework SwiftUI -framework AppKit -framework WebKit
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/AppIcon.icns" ]; then
  cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
rm -rf "/Applications/DAAK Duffy.app"
cp -R "$APP" "/Applications/DAAK Duffy.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/DAAK Duffy.app" 2>/dev/null || true
# Uygulamayı LaunchAgent yönetiyor; killall + open iki kopya açar
if launchctl print "gui/$(id -u)/app.daakduffy.system-ui" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/app.daakduffy.system-ui"
else
  open "/Applications/DAAK Duffy.app"
fi
echo "/Applications/DAAK Duffy.app"
