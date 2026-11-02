#!/bin/bash
# 把 .app 打包成 DMG。
#
# 用法：
#   ./tools/make_dmg.sh <路径/to/屏跃.app> <输出目录> [版本号]
#
# DMG 内结构：
#   屏跃.app
#   Applications -> /Applications   （拖拽安装的软链接）
#
# 签名说明：本项目用 ad-hoc 签名，无法做 Apple 公证（notarization），
# 用户首次打开需右键→打开，或执行 xattr -dr com.apple.quarantine /Applications/屏跃.app

set -euo pipefail

APP_PATH="${1:?用法: make_dmg.sh <app 路径> <输出目录> [版本号]}"
OUTPUT_DIR="${2:?用法: make_dmg.sh <app 路径> <输出目录> [版本号]}"
VERSION="${3:-1.0.0}"

# 包名。Finder 显示的是文件名而不是 CFBundleDisplayName，
# 所以想让用户看到「屏跃」，磁盘上的 .app 必须叫这个名字。
# 内部可执行文件仍为 DisplayHop（由 CFBundleExecutable 指定）。
BUNDLE_DISPLAY_NAME="屏跃"

if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ 找不到 App: $APP_PATH" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
DMG_NAME="${BUNDLE_DISPLAY_NAME}-${VERSION}-universal.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

STAGING="$(mktemp -d)"
cleanup() {
    # 卸载可能已挂载的卷
    if [[ -n "${MOUNT_DIR:-}" ]] && mount | grep -q "$MOUNT_DIR"; then
        hdiutil detach "$MOUNT_DIR" -quiet -force 2>/dev/null || true
    fi
    rm -rf "$STAGING"
}
trap cleanup EXIT

# 1. 准备 DMG 内容（包名改为中文）
cp -R "$APP_PATH" "$STAGING/${BUNDLE_DISPLAY_NAME}.app"
ln -s /Applications "$STAGING/Applications"

# 2. 创建 DMG
rm -f "$DMG_PATH"
hdiutil create \
    -volname "${BUNDLE_DISPLAY_NAME} ${VERSION}" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" >/dev/null

echo "✓ 已生成: $DMG_PATH"
ls -lh "$DMG_PATH" | awk '{print "  大小: " $5}'
