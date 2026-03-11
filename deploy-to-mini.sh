#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Rockpile 远程部署脚本
# ═══════════════════════════════════════════════════════════
#
# 用法:  bash deploy-to-mini.sh [build]
#
# 参数:
#   build  — 先编译再部署（默认只推送已编译的 .app）
#
# 流程:
#   1. [可选] xcodegen + xcodebuild Release 编译
#   2. 压缩 .app → tar.gz（~1MB）
#   3. scp 推送到 Mac Mini（通过 Tailscale）
#   4. 远程关闭旧版 → 解压覆盖 → 完成
#   5. 验证版本一致
#
# 前提:
#   - Tailscale 已连接
#   - SSH 免密登录已配置（id_ed25519）
#   - Mac Mini: sudo chown -R $USER:staff /Applications/Rockpile.app（一次性）

set -euo pipefail

# ── 配置 ──
MINI_USER="${MINI_USER:-your-username}"
MINI_HOST="${MINI_HOST:-your-mac-mini-ip}"
MINI="${MINI_USER}@${MINI_HOST}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_APP="/Applications/Rockpile.app"
REMOTE_APP="/Applications/Rockpile.app"
REMOTE_TMP="/tmp/Rockpile.app.tar.gz"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

step()  { echo -e "\n${CYAN}▶${NC} ${BOLD}$1${NC}"; }
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }

echo -e "${BOLD}"
echo "  🦞 Rockpile 远程部署"
echo "  目标: ${MINI} (Mac Mini via Tailscale)"
echo -e "${NC}"

# ── 1. 检查连通性 ──
step "检查连通性"
if ssh -o ConnectTimeout=5 "$MINI" "echo ok" &>/dev/null; then
    REMOTE_VER=$(ssh "$MINI" "defaults read ${REMOTE_APP}/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo '未安装'")
    ok "SSH 连接成功 — Mac Mini 当前: v${REMOTE_VER}"
else
    fail "无法连接 Mac Mini ($MINI_HOST)"
    echo -e "  ${RED}请检查: Tailscale 是否在线 / SSH 密钥 / 远程登录${NC}"
    exit 1
fi

# ── 2. 可选：编译 ──
if [[ "${1:-}" == "build" ]]; then
    step "编译 Release 版本"
    cd "$PROJECT_DIR"

    echo "  生成 Xcode 项目..."
    xcodegen generate 2>&1 | tail -1

    echo "  编译中（请稍等）..."
    xcodebuild -project Rockpile.xcodeproj \
        -scheme Rockpile \
        -configuration Release \
        -derivedDataPath build \
        CODE_SIGNING_ALLOWED=NO \
        SWIFT_STRICT_CONCURRENCY=complete \
        2>&1 | tail -3

    ok "编译完成"

    # 生成完整 .icns（Xcode 只生成部分尺寸，需要手动补全）
    APP_SRC="build/Build/Products/Release/Rockpile.app"
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
        ok "完整 .icns 已生成（10 个尺寸）"
    fi

    # 更新本机（先关闭再替换）
    if [[ -d "$APP_SRC" ]]; then
        killall Rockpile 2>/dev/null || true
        sleep 0.3
        rm -rf "$LOCAL_APP"
        cp -R "$APP_SRC" "$LOCAL_APP"
        /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f -R "$LOCAL_APP"
        ok "本机已更新: $LOCAL_APP"
    fi
fi

# ── 3. 检查本地 .app ──
if [[ ! -d "$LOCAL_APP" ]]; then
    fail "找不到 $LOCAL_APP"
    echo "  请先运行: bash deploy-to-mini.sh build"
    exit 1
fi

LOCAL_VER=$(defaults read "${LOCAL_APP}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
LOCAL_HASH=$(md5 -q "${LOCAL_APP}/Contents/MacOS/Rockpile" 2>/dev/null || echo "?")
ok "本地版本: v${LOCAL_VER}  hash: ${LOCAL_HASH:0:8}"

# ── 4. 压缩 + 推送 ──
step "压缩并推送"
LOCAL_TAR="/tmp/Rockpile.app.tar.gz"
tar -czf "$LOCAL_TAR" -C /Applications Rockpile.app
TAR_SIZE=$(du -h "$LOCAL_TAR" | cut -f1)
echo "  压缩完成: ${TAR_SIZE}"

scp -q "$LOCAL_TAR" "${MINI}:${REMOTE_TMP}"
ok "已传输 ${TAR_SIZE} → Mac Mini"
rm -f "$LOCAL_TAR"

# ── 5. 同步测试脚本 ──
TEST_SCRIPT="${PROJECT_DIR}/rockpile-test.sh"
if [[ -f "$TEST_SCRIPT" ]]; then
    scp -q "$TEST_SCRIPT" "${MINI}:~/Desktop/rockpile-test.sh"
    ok "测试脚本已同步"
fi

# ── 6. 远程替换 ──
step "远程安装"
ssh "$MINI" "
    # 关闭正在运行的 Rockpile
    killall Rockpile 2>/dev/null || true
    sleep 0.5

    # 备份旧版（以防万一）
    if [[ -d '${REMOTE_APP}' ]]; then
        rm -rf /tmp/Rockpile.app.bak
        mv '${REMOTE_APP}' /tmp/Rockpile.app.bak
    fi

    # 解压新版
    tar -xzf '${REMOTE_TMP}' -C /Applications/
    rm -f '${REMOTE_TMP}'

    # 验证新版可用，否则回滚
    if [[ -d '${REMOTE_APP}' ]] && [[ -f '${REMOTE_APP}/Contents/Info.plist' ]]; then
        echo 'OK'
    else
        echo 'EXTRACT_FAILED'
        if [[ -d /tmp/Rockpile.app.bak ]]; then
            mv /tmp/Rockpile.app.bak '${REMOTE_APP}'
            echo 'ROLLED_BACK'
        fi
    fi
"

# 检查远程输出
if ssh "$MINI" "test -d '${REMOTE_APP}'" 2>/dev/null; then
    ok "远程替换完成"
else
    fail "远程安装失败，已回滚到旧版"
    exit 1
fi

# ── 7. 验证 (hash 比对) ──
step "验证"
FINAL_VER=$(ssh "$MINI" "defaults read ${REMOTE_APP}/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo '?'")
REMOTE_HASH=$(ssh "$MINI" "md5 -q ${REMOTE_APP}/Contents/MacOS/Rockpile 2>/dev/null || echo '?'")

if [[ "$LOCAL_HASH" == "$REMOTE_HASH" && "$LOCAL_HASH" != "?" ]]; then
    ok "Build hash 一致: ${LOCAL_HASH:0:8} ✅"
else
    warn "Hash 不一致 — 本地 ${LOCAL_HASH:0:8} / 远程 ${REMOTE_HASH:0:8}"
fi

if [[ "$FINAL_VER" == "$LOCAL_VER" ]]; then
    ok "版本一致: v${FINAL_VER}"
fi

# ── 8. 重启两端 ──
step "重启应用"

# 远程重启
ssh "$MINI" "open /Applications/Rockpile.app" 2>/dev/null
ok "远程 Rockpile 已启动"

# 等待远程启动
sleep 3
if ssh "$MINI" "pgrep -x Rockpile" &>/dev/null; then
    ok "远程进程确认运行中"
else
    warn "远程进程未检测到（可能需要手动启动）"
fi

# 本机重启
killall Rockpile 2>/dev/null || true
sleep 0.5
open /Applications/Rockpile.app
ok "本机 Rockpile 已重启"

echo ""
echo -e "${GREEN}${BOLD}  🦞 部署完成！${NC}"
echo -e "  Mac Mini: v${FINAL_VER}  hash: ${REMOTE_HASH:0:8}"
echo -e "  本机:     v${LOCAL_VER}  hash: ${LOCAL_HASH:0:8}"
echo ""
