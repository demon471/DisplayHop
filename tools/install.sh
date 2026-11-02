#!/bin/bash
# 构建 Release 版本并安装到 /Applications。
#
# 为什么要装到 /Applications 而不是一直用 Xcode 的 Debug 产物：
#   本项目没有开发者证书，用的是 ad-hoc 签名（CODE_SIGN_IDENTITY = "-"）。
#   ad-hoc 签名每次重新构建都会变，macOS 会当成一个新 App，
#   于是辅助功能列表里会不断堆积重复条目、且需要反复授权。
#   装到 /Applications 后不再重新构建，权限授一次即可长期有效。
#
# 用法：./tools/install.sh

set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="com.johnbebee.DisplayHop"
APP_NAME="DisplayHop.app"
# 安装后的中文名。Finder 显示的是文件名，CFBundleDisplayName 只影响其他 UI，
# 所以想让 Finder / 权限列表都显示中文，必须把包名改成中文。
DEST_NAME="屏跃.app"
DEST="/Applications/$DEST_NAME"

echo "==> 生成工程"
xcodegen generate >/dev/null

echo "==> 构建 Release"
xcodebuild -project DisplayHop.xcodeproj \
    -scheme DisplayHop \
    -configuration Release \
    -destination 'platform=macOS' \
    build 2>&1 | grep -E "error:|BUILD" | tail -3

BUILT=$(find ~/Library/Developer/Xcode/DerivedData/DisplayHop-*/Build/Products/Release \
    -maxdepth 1 -name "$APP_NAME" 2>/dev/null | head -1)

if [[ -z "${BUILT:-}" ]]; then
    echo "✗ 没找到构建产物" >&2
    exit 1
fi

echo "==> 退出正在运行的实例"
pkill -x DisplayHop 2>/dev/null || true
sleep 1

echo "==> 安装到 $DEST"
rm -rf "$DEST"
# 清掉旧英文名的安装（如果有）
rm -rf "/Applications/DisplayHop.app"
cp -R "$BUILT" "$DEST"

# 注销 Xcode 构建产物的 LaunchServices 注册。
# 否则系统会把这些副本当成额外的同名 App，权限列表里会出现多条重复条目
# （且图标是空白，因为 DerivedData 产物没有完整的图标注册）。
LSR="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
for stale in "$HOME"/Library/Developer/Xcode/DerivedData/DisplayHop-*/Build/Products/*/DisplayHop.app; do
    [[ -d "$stale" ]] && "$LSR" -u "$stale" 2>/dev/null || true
done
"$LSR" -f "$DEST" 2>/dev/null || true

# 清掉旧权限条目，避免列表里堆一堆失效的重复项。
# 注意：ad-hoc 签名每次重新构建都会变，系统会当成新 App，
# 所以重装后必须重新授权一次（这也是 macOS 对未公证 App 的固有行为）。
echo "==> 重置辅助功能授权记录（需要重新勾选一次）"
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

echo "==> 启动"
open "$DEST"

echo
echo "完成。"
echo "  1. 在「系统设置 → 隐私与安全性 → 辅助功能」中勾选「屏跃」"
echo "  2. 首次打开若被 Gatekeeper 拦截，右键点击 App → 打开，或执行："
echo "     xattr -dr com.apple.quarantine \"$DEST\""
