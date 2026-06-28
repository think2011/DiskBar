#!/bin/bash
# 编译 DiskBar.app（无需 Xcode，仅用 Command Line Tools 的 swiftc）。
# 用法: ./build.sh [输出目录]   默认输出到桌面
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DiskBar"
DEST="${1:-$HOME/Desktop}"
APP="$DEST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "==> 清理旧 app: $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

echo "==> 编译可执行文件"
swiftc -O \
  -o "$MACOS/$APP_NAME" \
  Sources/*.swift \
  -framework AppKit -framework SwiftUI

echo "==> 写入 Info.plist"
cp Info.plist "$CONTENTS/Info.plist"

if [ -f "Resources/AppIcon.icns" ]; then
  echo "==> 拷贝图标"
  cp Resources/AppIcon.icns "$RES/AppIcon.icns"
fi

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "   (签名跳过)"

echo "==> 完成: $APP"
