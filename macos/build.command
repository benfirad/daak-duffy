#!/bin/zsh
# DAAK Duffy menü çubuğu uygulamasını derler ve /Applications'a kurar.
# Xcode projesi gerekmez; Xcode Command Line Tools yeterli.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/DAAK Duffy.app"
DEST="${DUFFY_APP_DEST:-/Applications/DAAK Duffy.app}"
LABEL="${DUFFY_APP_LABEL:-app.daakduffy.system-ui}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun --sdk macosx swiftc -parse-as-library -O \
  -target "$(uname -m)-apple-macos13.0" \
  -o "$APP/Contents/MacOS/daakDuffy" \
  "$ROOT"/Sources/*.swift \
  -framework SwiftUI -framework AppKit
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/AppIcon.icns" ]; then
  cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

[ "${1:-}" = "--no-install" ] && { echo "$APP"; exit 0; }

PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

# Önce durdur: KeepAlive'lı LaunchAgent, paket yarı kopyalanmışken uygulamayı yeniden
# başlatırsa macOS imzayı geçersiz sayıp öldürür (Launch Constraint Violation).
if [ -f "$PLIST" ]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
fi
pkill -x daakDuffy 2>/dev/null || true
for _ in {1..20}; do pgrep -x daakDuffy >/dev/null || break; sleep 0.25; done

# Yeni paketi yanına kopyala, sonra tek hamlede yer değiştir
rm -rf "$DEST.new" "$DEST.old"
cp -R "$APP" "$DEST.new"
[ -e "$DEST" ] && mv "$DEST" "$DEST.old"
mv "$DEST.new" "$DEST"
rm -rf "$DEST.old"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null || true

if [ -f "$PLIST" ]; then
  launchctl bootstrap "$DOMAIN" "$PLIST"
else
  open "$DEST"
fi
echo "$DEST"
