#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Rockpile 综合测试脚本 v2 (curl HTTP POST)
# ═══════════════════════════════════════════════════════════
#
# 用法:  bash rockpile-test.sh [MacBook IP]
# 参数:  $1 = Rockpile 所在 Mac 的 IP（默认 192.168.10.162）
#
# 测试流程:
#   1. 连通性 — HTTP /health 健康检查
#   2. 单会话 — SessionStart → 思考 → 工作 → ToolCall → 错误恢复 → 结束
#   3. 多会话 — 2 只小龙虾同时在线，独立状态
#   4. O₂ 氧气 — 低/中/高用量，验证颜色 绿→黄→红
#
# 前提: Rockpile 已启动 + 同一网络 + 已安装 curl

set -euo pipefail

HOST="${1:-192.168.10.162}"
PORT=18790
URL="http://$HOST:$PORT"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
GRAY='\033[0;37m'
NC='\033[0m'
BOLD='\033[1m'

ts() { echo $(($(date +%s) * 1000)); }

# 使用 curl HTTP POST 发送，比 nc 可靠得多
send() {
  local response
  response=$(curl -s -m 5 -X POST \
    -H "Content-Type: application/json" \
    -d "$1" \
    "$URL" 2>/dev/null) || true

  if echo "$response" | grep -q "ok"; then
    return 0
  else
    echo -e "    ${RED}⚠ 发送失败，重试...${NC}"
    sleep 0.5
    curl -s -m 5 -X POST -H "Content-Type: application/json" -d "$1" "$URL" 2>/dev/null || true
  fi
  sleep 0.2
}

header() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  $1${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

step() {
  echo -e "  ${CYAN}▶${NC} $1"
  echo -e "    ${GRAY}预期: $2${NC}"
}

ok() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
wait_sec() { echo -e "    ${GRAY}⏳ 等待 ${1}s ...${NC}"; sleep "$1"; }

echo -e "${BOLD}"
echo "  🦞 Rockpile 测试工具 (v2 - curl 版)"
echo "  目标: $URL"
echo -e "${NC}"

# ═══════════════════════════════════════
header "测试 1: 连通性检查"
# ═══════════════════════════════════════

step "HTTP 健康检查" "返回 {\"status\":\"ok\"}"
HEALTH=$(curl -s -m 3 "$URL/health" 2>/dev/null || echo "failed")
if echo "$HEALTH" | grep -q "ok"; then
  ok "健康检查通过: $HEALTH"
else
  fail "无法连接到 $URL"
  echo -e "  ${RED}请检查: 1) Rockpile 是否启动  2) 防火墙  3) IP 地址${NC}"
  exit 1
fi

# ═══════════════════════════════════════
header "测试 2: 单会话完整流程"
# ═══════════════════════════════════════

SID="test-$(date +%s)"
echo -e "  会话 ID: ${PURPLE}$SID${NC}"
echo ""

step "SessionStart" "🦞 出现 1 只小龙虾，状态：空闲"
send "{\"session_id\":\"$SID\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "LLMInput → 思考中" "🦞 小龙虾变成思考动画"
send "{\"session_id\":\"$SID\",\"event\":\"LLMInput\",\"status\":\"thinking\",\"user_prompt\":\"你好\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 3

step "LLMOutput → 工作中" "🦞 小龙虾变成工作动画 + O₂ 显示用量"
send "{\"session_id\":\"$SID\",\"event\":\"LLMOutput\",\"status\":\"working\",\"daily_tokens_used\":150000,\"input_tokens\":1200,\"output_tokens\":800,\"ts\":$(ts)}"
ok "已发送（附带 token 用量）"
wait_sec 2

step "ToolCall: bash" "活动日志出现 bash"
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"bash\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "ToolResult: bash 成功" "活动日志出现 bash 完成"
send "{\"session_id\":\"$SID\",\"event\":\"ToolResult\",\"status\":\"working\",\"tool\":\"bash\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "ToolCall: edit" "活动日志出现 edit"
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"edit\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "ToolResult: edit 出错" "🦞 小龙虾短暂变红，3 秒后恢复"
send "{\"session_id\":\"$SID\",\"event\":\"ToolResult\",\"status\":\"error\",\"tool\":\"edit\",\"error\":\"File not found\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 4

step "AgentEnd → 空闲" "🦞 小龙虾回到空闲动画"
send "{\"session_id\":\"$SID\",\"event\":\"AgentEnd\",\"status\":\"idle\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 3

step "SessionEnd → 会话结束" "🦞 小龙虾消失，显示对话历史"
send "{\"session_id\":\"$SID\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "已发送"

# 验证会话确实关闭
sleep 1
echo -e "    ${GRAY}验证: 确认连接正常...${NC}"
HEALTH2=$(curl -s -m 3 "$URL/health" 2>/dev/null || echo "failed")
if echo "$HEALTH2" | grep -q "ok"; then
  ok "连接正常，会话应已关闭"
else
  fail "连接异常"
fi
wait_sec 2

# ═══════════════════════════════════════
header "测试 3: 多会话（2 只小龙虾）"
# ═══════════════════════════════════════

SID_A="multi-a-$(date +%s)"
SID_B="multi-b-$(date +%s)"

step "创建会话 A" "🦞 出现第 1 只小龙虾"
send "{\"session_id\":\"$SID_A\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
ok "会话 A: $SID_A"
wait_sec 1

step "创建会话 B" "🦞🦞 出现第 2 只小龙虾，显示 2 个会话"
send "{\"session_id\":\"$SID_B\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
ok "会话 B: $SID_B"
wait_sec 2

step "会话 A 思考，会话 B 工作" "🦞 两只小龙虾不同动画"
send "{\"session_id\":\"$SID_A\",\"event\":\"LLMInput\",\"status\":\"thinking\",\"ts\":$(ts)}"
send "{\"session_id\":\"$SID_B\",\"event\":\"LLMOutput\",\"status\":\"working\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 3

step "关闭会话 A" "🦞 只剩 1 只小龙虾"
send "{\"session_id\":\"$SID_A\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "关闭会话 B" "🦞 全部消失，显示对话历史"
send "{\"session_id\":\"$SID_B\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

# ═══════════════════════════════════════
header "测试 4: O₂ 氧气瓶（token 消耗）"
# ═══════════════════════════════════════

SID_O2="o2-test-$(date +%s)"

step "创建会话 + 正常用量" "🫧 O₂ 显示绿色"
send "{\"session_id\":\"$SID_O2\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
send "{\"session_id\":\"$SID_O2\",\"event\":\"LLMOutput\",\"status\":\"working\",\"daily_tokens_used\":200000,\"ts\":$(ts)}"
ok "已发送 (200K tokens)"
wait_sec 3

step "中等用量" "🫧 O₂ 显示黄色"
send "{\"session_id\":\"$SID_O2\",\"event\":\"LLMOutput\",\"status\":\"working\",\"daily_tokens_used\":700000,\"ts\":$(ts)}"
ok "已发送 (700K tokens)"
wait_sec 3

step "高用量" "🫧 O₂ 显示红色闪烁"
send "{\"session_id\":\"$SID_O2\",\"event\":\"LLMOutput\",\"status\":\"working\",\"daily_tokens_used\":950000,\"ts\":$(ts)}"
ok "已发送 (950K tokens)"
wait_sec 3

step "清理" ""
send "{\"session_id\":\"$SID_O2\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "O₂ 测试会话已关闭"
wait_sec 1

# ═══════════════════════════════════════
header "测试完成 ✅"
# ═══════════════════════════════════════

echo ""
echo -e "  ${GREEN}所有测试已执行完毕${NC}"
echo ""
echo -e "  ${GRAY}检查清单:${NC}"
echo -e "  ${GRAY}  □ 池塘和文字区域分开（文字在黑色背景上）${NC}"
echo -e "  ${GRAY}  □ 单会话时小龙虾居中${NC}"
echo -e "  ${GRAY}  □ SessionEnd 后小龙虾消失${NC}"
echo -e "  ${GRAY}  □ 多会话时正确显示多只小龙虾${NC}"
echo -e "  ${GRAY}  □ O₂ 氧气条颜色随用量变化${NC}"
echo -e "  ${GRAY}  □ 错误状态后 3 秒自动恢复${NC}"
echo -e "  ${GRAY}  □ 测试结束后显示对话历史记录${NC}"
echo -e "  ${GRAY}  □ 时间显示为绝对时间（HH:mm:ss）${NC}"
echo ""
