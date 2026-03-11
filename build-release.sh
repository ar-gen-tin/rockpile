#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Rockpile — Release 签名 + DMG 打包 + 公证
# ═══════════════════════════════════════════════════════════
#
# 用法:
#   bash build-release.sh           # 仅编译 + 签名 + DMG
#   bash build-release.sh notarize  # 编译 + 签名 + DMG + 公证
#
# 前提:
#   1. Developer ID Application 证书已安装（Xcode → Settings → Accounts → Manage Certificates）
#   2. TEAM_ID 已填写（下方配置）
#   3. 公证需要：APPLE_ID + APP_SPECIFIC_PASSWORD（https://appleid.apple.com → App-Specific Passwords）
#   4. brew install create-dmg
#
# 产出:
#   dist/Rockpile-v2.0.5.dmg     — 可分发的 DMG 安装包
#   dist/Rockpile.app             — 签名后的 app

set -euo pipefail

# ═══════════════════════════════════════════════════════════
# 🔧 配置 — 请填入你的信息
# ═══════════════════════════════════════════════════════════
TEAM_ID="${TEAM_ID:-}"                                 # Apple Developer Team ID
APPLE_ID="${APPLE_ID:-}"                               # ← 你的 Apple ID（公证用）
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-}"      # ← App-Specific Password（公证用）
# ═══════════════════════════════════════════════════════════

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${PROJECT_DIR}/dist"
BUILD_DIR="${PROJECT_DIR}/build"
APP_NAME="Rockpile"
BUNDLE_ID="com.rockpile.app"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

step()  { echo -e "\n${CYAN}▶${NC} ${BOLD}$1${NC}"; }
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; exit 1; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }

echo -e "${BOLD}"
echo "  🦞 Rockpile Release Builder"
echo -e "${NC}"

# ── 0. 前置检查 ──
step "前置检查"

if [[ -z "$TEAM_ID" ]]; then
    fail "请在脚本顶部填入 TEAM_ID（Apple Developer Team ID）"
fi

# 检查签名证书
SIGN_IDENTITY="Developer ID Application"
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    fail "未找到 '${SIGN_IDENTITY}' 证书。请在 Xcode → Settings → Accounts → Manage Certificates 中创建"
fi
ok "签名证书就绪"

if ! command -v create-dmg &>/dev/null; then
    fail "未安装 create-dmg。运行: brew install create-dmg"
fi
ok "create-dmg 就绪"

# ── 1. 编译 Release ──
step "编译 Release"
cd "$PROJECT_DIR"

xcodegen generate 2>&1 | tail -1

xcodebuild -project Rockpile.xcodeproj \
    -scheme Rockpile \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--options runtime" \
    SWIFT_STRICT_CONCURRENCY=complete \
    2>&1 | tail -5

APP_SRC="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$APP_SRC" ]]; then
    fail "编译产物不存在: $APP_SRC"
fi
ok "编译完成"

# ── 2. 生成完整 .icns ──
ICON_SRC="Rockpile/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
if [[ -f "$ICON_SRC" ]]; then
    ICONSET_DIR="/tmp/Rockpile.iconset"
    rm -rf "$ICONSET_DIR" && mkdir -p "$ICONSET_DIR"
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png"    >/dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET_DIR" -o "${APP_SRC}/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    ok "完整 .icns 已生成"
fi

# ── 3. 代码签名（强制重签 + hardened runtime） ──
step "代码签名"

codesign --force --deep --options runtime \
    --sign "$SIGN_IDENTITY" \
    --entitlements "Rockpile/Rockpile.entitlements" \
    --timestamp \
    "$APP_SRC"

# 验证签名
codesign --verify --deep --strict --verbose=2 "$APP_SRC" 2>&1 | tail -3
ok "签名验证通过"

# 检查 hardened runtime
SIGN_FLAGS=$(codesign -d --verbose=4 "$APP_SRC" 2>&1 | grep "flags=" || echo "")
if echo "$SIGN_FLAGS" | grep -q "runtime"; then
    ok "Hardened Runtime 已启用"
else
    warn "Hardened Runtime 标志未检测到"
fi

# ── 4. 创建 DMG ──
step "创建 DMG"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 复制 app 到 dist
cp -R "$APP_SRC" "${DIST_DIR}/${APP_NAME}.app"

VERSION=$(defaults read "${APP_SRC}/Contents/Info.plist" CFBundleShortVersionString)
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"

# 清理可能残留的旧 DMG
rm -f "$DMG_PATH"

create-dmg \
    --volname "$APP_NAME" \
    --volicon "${APP_SRC}/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 175 190 \
    --app-drop-link 425 190 \
    --hide-extension "$APP_NAME.app" \
    --no-internet-enable \
    "$DMG_PATH" \
    "${DIST_DIR}/${APP_NAME}.app"

ok "DMG 创建完成: ${DMG_NAME}"

# 签名 DMG
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
ok "DMG 已签名"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo -e "  📦 ${BOLD}${DMG_PATH}${NC} (${DMG_SIZE})"

# ── 5. 公证（可选） ──
if [[ "${1:-}" == "notarize" ]]; then
    step "提交公证"

    if [[ -z "$APPLE_ID" || -z "$APP_SPECIFIC_PASSWORD" ]]; then
        fail "公证需要配置 APPLE_ID 和 APP_SPECIFIC_PASSWORD"
    fi

    echo "  提交中（通常需要 2-5 分钟）..."

    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_SPECIFIC_PASSWORD" \
        --wait \
        2>&1 | tee /tmp/notarize-output.txt

    if grep -q "status: Accepted" /tmp/notarize-output.txt; then
        ok "公证通过！"

        # Staple — 将公证票据嵌入 DMG
        step "Staple 票据"
        xcrun stapler staple "$DMG_PATH"
        ok "票据已嵌入 DMG"
    else
        warn "公证未通过，请查看详细日志:"
        # 提取 submission ID 查看日志
        SUB_ID=$(grep -o 'id: [a-f0-9-]*' /tmp/notarize-output.txt | head -1 | cut -d' ' -f2)
        if [[ -n "$SUB_ID" ]]; then
            echo "  查看详情: xcrun notarytool log $SUB_ID --apple-id $APPLE_ID --team-id $TEAM_ID --password ***"
        fi
    fi
    rm -f /tmp/notarize-output.txt
else
    echo ""
    warn "跳过公证。运行 'bash build-release.sh notarize' 进行公证"
fi

# ── 完成 ──
echo ""
echo -e "${GREEN}${BOLD}  🦞 Release 构建完成！${NC}"
echo -e "  版本: v${VERSION}"
echo -e "  DMG:  ${DMG_PATH}"
echo -e "  大小: ${DMG_SIZE}"
echo ""
echo -e "  ${CYAN}分发步骤:${NC}"
echo -e "  1. 公证:    bash build-release.sh notarize"
echo -e "  2. 上传:    GitHub Release / 网站 / 直接分享"
echo ""
