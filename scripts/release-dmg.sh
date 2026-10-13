#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$PROJECT_ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' MacIsland/Info.plist)
mkdir -p work release
DMG="$PROJECT_ROOT/release/MacIsland-${VERSION}-universal.dmg"
[[ ! -e "$DMG" ]] || { print -u2 "Already exists: $DMG"; exit 1; }
xcodebuild -project MacIsland.xcodeproj -scheme MacIsland -configuration Release \
  -derivedDataPath build-universal ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build > work/build-universal.log 2>&1
APP="$PROJECT_ROOT/build-universal/Build/Products/Release/MacIsland.app"
codesign --verify --deep --strict "$APP"
BINARY_ARCHS=$(xcrun lipo -archs "$APP/Contents/MacOS/MacIsland")
[[ "$BINARY_ARCHS" == *arm64* && "$BINARY_ARCHS" == *x86_64* ]] || { print -u2 "Missing architecture: $BINARY_ARCHS"; exit 1; }
STAGING=$(mktemp -d "$PROJECT_ROOT/work/dmg-stage.XXXXXX")
ditto "$APP" "$STAGING/MacIsland.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/INSTALL.txt" <<'INSTALL'
MacIsland / 安装与使用

Drag MacIsland.app into Applications, then launch it from Applications.
将 MacIsland.app 拖到 Applications，然后从“应用程序”启动。

Settings → Language / 语言: 简体中文 or English.
Window control requires Accessibility permission. Hovering does not.
窗口控制需要辅助功能权限；仅悬停无需授权。

This release is ad-hoc signed and is NOT Apple notarized.
Gatekeeper may block downloaded copies. Source: https://github.com/PoetHeart/MacIsland
本版本使用 ad-hoc 签名，未经 Apple 公证，下载后可能被系统拦截。
macOS 14+ / Apple Silicon + Intel
INSTALL
hdiutil create -volname "MacIsland $VERSION" -srcfolder "$STAGING" -format UDZO "$DMG"
hdiutil verify "$DMG"
(cd release && shasum -a 256 "${DMG:t}" > "MacIsland-${VERSION}-SHA256.txt")
print "Ready: $DMG"
