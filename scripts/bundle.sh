#!/bin/sh
# Builds AulaStudio.app (release) into ./dist with an Info.plist and icon.
set -e
cd "$(dirname "$0")/.."
swift build -c release --product AulaStudio
APP=dist/AulaStudio.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AulaStudio "$APP/Contents/MacOS/AulaStudio"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>AulaStudio</string>
  <key>CFBundleDisplayName</key><string>Aula Studio</string>
  <key>CFBundleIdentifier</key><string>dev.aulastudio.app</string>
  <key>CFBundleVersion</key><string>${VERSION:-1}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-0.1.0}</string>
  <key>CFBundleExecutable</key><string>AulaStudio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
EOF
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
