#!/bin/zsh
# Builds build/ScreenTune.app. Needs only the Xcode Command Line Tools.
set -e
cd "$(dirname "$0")"
swift build -c release
app=build/ScreenTune.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/ScreenTune "$app/Contents/MacOS/ScreenTune"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ScreenTune</string>
  <key>CFBundleIdentifier</key><string>com.nate.screentune</string>
  <key>CFBundleExecutable</key><string>ScreenTune</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "Built $app"
