#!/bin/bash
# 把 .app 打包成 DMG。
#
# 用法：
#   ./tools/make_dmg.sh <路径/to/DisplayHop.app> <输出目录> <版本号> [架构]
#
# 架构：arm64 | x64 | universal（默认 universal）
#
# 产物名用英文（DisplayHop-1.0.0-arm64.dmg）：
# GitHub Release 的资源名会把非 ASCII 字符吞掉，中文名会变成「-1.0.0-arm64.dmg」。
#
# DMG 内的 App 名保持中文「屏跃.app」，Finder 里显示的是文件名，
# 菜单栏/Dock/关于面板显示的是本地化后的名字。

set -euo pipefail

APP_PATH="${1:?用法: make_dmg.sh <app 路径> <输出目录> <版本号> [架构]}"
OUTPUT_DIR="${2:?用法: make_dmg.sh <app 路径> <输出目录> <版本号> [架构]}"
VERSION="${3:?用法: make_dmg.sh <app 路径> <输出目录> <版本号> [架构]}"
ARCH="${4:-universal}"

# 产物用英文名，DMG 卷名用英文；App 名保持中文。
BUNDLE_DISPLAY_NAME="屏跃"
ARTIFACT_BASE_NAME="DisplayHop"

if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ 找不到 App: $APP_PATH" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
DMG_NAME="${ARTIFACT_BASE_NAME}-${VERSION}-${ARCH}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

STAGING="$(mktemp -d)"
cleanup() {
    if [[ -n "${MOUNT_DIR:-}" ]] && mount | grep -q "$MOUNT_DIR"; then
        hdiutil detach "$MOUNT_DIR" -quiet -force 2>/dev/null || true
    fi
    rm -rf "$STAGING"
}
trap cleanup EXIT

# 1. 准备 DMG 内容
cp -R "$APP_PATH" "$STAGING/${BUNDLE_DISPLAY_NAME}.app"
ln -s /Applications "$STAGING/Applications"

# 2. 创建 DMG（卷名用英文，避免某些工具对中文卷名的兼容问题）
rm -f "$DMG_PATH"
hdiutil create \
    -volname "${ARTIFACT_BASE_NAME} ${VERSION}" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" >/dev/null

echo "✓ 已生成: $DMG_PATH"
ls -lh "$DMG_PATH" | awk '{print "  大小: " $5}'
