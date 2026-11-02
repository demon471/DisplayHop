#!/bin/bash
# 从 git tag 解析版本号，输出到 GITHUB_OUTPUT（CI）或 stdout（本地）。
#
# 用法：
#   TAG=v1.2.0 ./tools/version.sh
#   TAG=v1.2.0 ./tools/version.sh --github
#
# 输出：
#   marketing_version   CFBundleShortVersionString，如 1.2.0
#   build_number        CFBundleVersion，必须是正整数
#
# 规则：
#   tag 去掉开头的 v → 取前三段数字作为版本号（1.2.3）
#   预发布后缀（-beta.1）不进入版本号，避免 CFBundleShortVersionString 非数字段
#   build_number 优先用 tag 里的构建号（v1.2.0-45 → 45），
#   否则用 GITHUB_RUN_NUMBER，最后回退到 1
#
# 注意：--github 标志不限定位置（之前写成 $2 时，CI 里
# "./tools/version.sh --github" 会把标志落到 $1，导致结果没写进 GITHUB_OUTPUT）

set -euo pipefail

GITHUB_MODE=""
for arg in "$@"; do
    case "$arg" in
        --github) GITHUB_MODE="--github" ;;
    esac
done

TAG="${TAG:-${1:-}}"
if [[ -z "$TAG" || "$TAG" == "--github" ]]; then
    echo "用法: TAG=v1.2.0 $0 [--github]" >&2
    exit 1
fi

# 去掉 refs/tags/ 前缀和开头的 v
TAG="${TAG#refs/tags/}"
TAG="${TAG#v}"

# 取前三段纯数字段作为版本号：1.2.3
MARKETING_VERSION=$(echo "$TAG" | sed -E 's/[^0-9.]+/./g; s/\.+/./g; s/^\.//; s/\.$//' | cut -d. -f1-3)
if [[ -z "$MARKETING_VERSION" ]]; then
    MARKETING_VERSION="1.0.0"
fi
# 保证至少三段
while [[ $(echo "$MARKETING_VERSION" | tr -cd '.' | wc -c) -lt 2 ]]; do
    MARKETING_VERSION="${MARKETING_VERSION}.0"
done

# build_number：只认显式的构建号后缀（-45 / +45），不把版本号末段当构建号
BUILD_NUMBER=$(echo "$TAG" | grep -oE '[-+][0-9]+$' | grep -oE '[0-9]+' || true)
if [[ -z "$BUILD_NUMBER" || "$BUILD_NUMBER" -lt 1 ]]; then
    BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
fi
if [[ "$BUILD_NUMBER" -lt 1 ]]; then
    BUILD_NUMBER=1
fi

if [[ "$GITHUB_MODE" == "--github" ]]; then
    echo "marketing_version=$MARKETING_VERSION" >> "$GITHUB_OUTPUT"
    echo "build_number=$BUILD_NUMBER" >> "$GITHUB_OUTPUT"
else
    echo "marketing_version=$MARKETING_VERSION"
    echo "build_number=$BUILD_NUMBER"
fi
