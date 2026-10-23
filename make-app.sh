#!/bin/zsh
# Builds Mushaf.app (release, ad-hoc signed) into ./build.
set -euo pipefail
cd "$(dirname "$0")"

# The macOS 27 Command Line Tools SDK expands @State through a macro plugin that ships only
# with Xcode; fall back to the 26.5 SDK when Xcode isn't selected.
if [[ "$(xcode-select -p)" == *CommandLineTools* && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MushafMac"
APP=build/Mushaf.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Mushaf"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mushaf</string>
  <key>CFBundleDisplayName</key><string>Mushaf</string>
  <key>CFBundleIdentifier</key><string>com.mkoussa.mushaf</string>
  <key>CFBundleExecutable</key><string>Mushaf</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.reference</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.mkoussa.mushaf</string>
    <key>CFBundleURLSchemes</key><array><string>mushaf</string></array>
  </dict></array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $PWD/$APP"
