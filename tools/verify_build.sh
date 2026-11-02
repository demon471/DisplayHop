#!/bin/bash
# 校验构建产物。CI（.github/workflows/build.yml）和本地都调用这一个脚本，
# 避免两边各写一份、路径写法不一致导致 CI 假失败。
#
# 用法：./tools/verify_build.sh [App 路径]

set -euo pipefail

APP="${1:-build/DerivedData/Build/Products/Release/DisplayHop.app}"
EXPECTED_VERSION="${2:-}"

fail() {
    echo "✗ $1" >&2
    exit 1
}

echo "==> 校验 App 包: $APP"

[[ -d "$APP" ]] || fail "App 目录不存在: $APP"
[[ -f "$APP/Contents/Info.plist" ]] || fail "Info.plist 缺失: $APP/Contents/Info.plist"
[[ -f "$APP/Contents/MacOS/DisplayHop" ]] || fail "可执行文件缺失: $APP/Contents/MacOS/DisplayHop"
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || fail "图标缺失: $APP/Contents/Resources/AppIcon.icns"
[[ -d "$APP/Contents/Resources/zh-Hans.lproj" ]] || fail "中文本地化缺失"
[[ -d "$APP/Contents/Resources/en.lproj" ]] || fail "英文本地化缺失"
echo "✓ 包结构完整"

echo "==> 校验 universal 架构"
BIN="$APP/Contents/MacOS/DisplayHop"
ARCHS=$(lipo -archs "$BIN")
echo "  architectures: $ARCHS"
echo "$ARCHS" | grep -q x86_64 || fail "缺少 x86_64 slice"
echo "$ARCHS" | grep -q arm64  || fail "缺少 arm64 slice"
# 确认是真正的 fat 二进制（而不是单架构）。
# 注意：lipo -detailed_info 输出的是小写 "architecture x86_64"，
# 用 file 判定 "universal binary" 更可靠。
file "$BIN" | grep -q "universal binary" || fail "不是 universal（fat）二进制: $(file "$BIN")"
echo "✓ universal binary OK"

echo "==> 校验版本号"
# 先确认键存在（Xcode 在版本号为空时会静默删除这两个键）
for key in CFBundleShortVersionString CFBundleVersion; do
    /usr/libexec/PlistBuddy -c "Print :$key" "$APP/Contents/Info.plist" >/dev/null 2>&1 \
        || fail "Info.plist 缺少 ${key}（版本号是否为空？）"
done
SHORT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
echo "  version: $SHORT ($BUILD)"
if [[ -n "$EXPECTED_VERSION" && "$SHORT" != "$EXPECTED_VERSION" ]]; then
    fail "版本号不匹配：期望 ${EXPECTED_VERSION}，实际 $SHORT"
fi

echo "==> 校验签名"
if codesign -dv "$APP" >/dev/null 2>&1; then
    SIGN=$(codesign -dv "$APP" 2>&1 | grep -oE 'Signature=.*' | head -1)
    echo "  $SIGN"
    # 签名无效时 Gatekeeper 会直接拒绝运行
    codesign --verify --deep --strict "$APP" || fail "签名校验失败"
    echo "✓ 签名有效"
else
    echo "  ⚠ 无签名（未签名 App 首次打开需右键→打开）"
fi

echo "✓ 全部校验通过"
