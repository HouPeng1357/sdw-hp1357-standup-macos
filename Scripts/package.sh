#!/bin/bash
# 打包 SDWStandup 为 .app bundle 并做 ad-hoc 签名。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="sdw-hp1357-standup-macos"
BIN_NAME="SDWStandup"
BUNDLE="dist/${APP_NAME}.app"

swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp ".build/release/${BIN_NAME}" "$BUNDLE/Contents/MacOS/"
cp "Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# ad-hoc 签名（SMAppService 登录项必需）
codesign --force --deep --sign - "$BUNDLE"

echo "OK: $BUNDLE"
