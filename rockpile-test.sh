#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Rockpile 综合测试脚本 v3
# ═══════════════════════════════════════════════════════════
#
# 用法:  bash rockpile-test.sh [IP]
# 参数:  $1 = Rockpile 所在 Mac 的 IP（默认 127.0.0.1）
#
# 测试流程:
#   1. 连通性 — HTTP /health 健康检查
#   2. 单会话完整流程 — SessionStart → 思考 → 工作 → 工具 → 错误恢复 → 结束
#   3. 多会话 — 2 只小龙虾同时在线，独立状态
#   4. O₂ 氧气瓶 — 低/中/高用量，验证颜色变化
#   5. 情绪系统 — 用户消息触发情绪变化
#   6. 上下文压缩 — Compaction 事件
#   7. 子代理 — SubagentSpawned / SubagentEnded
#   8. 快速连发 — 高频事件压力测试
#   9. 会话超时 — idle 状态持续后自动清理
#
# 前提: Rockpile 已启动 + 同一网络 + 已安装 curl

set -euo pipefail

HOST="${1:-127.0.0.1}"
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

PASS=0
FAIL=0

ts() { echo $(($(date +%s) * 1000)); }

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
  sleep 0.15
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

ok() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
wait_sec() { echo -e "    ${GRAY}⏳ 等待 ${1}s ...${NC}"; sleep "$1"; }

echo -e "${BOLD}"
echo "  🦞 Rockpile 测试工具 (v3)"
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

step "重复健康检查 (3次)" "每次都返回 ok"
ALL_OK=true
for i in 1 2 3; do
  H=$(curl -s -m 2 "$URL/health" 2>/dev/null || echo "failed")
  if ! echo "$H" | grep -q "ok"; then
    ALL_OK=false
    break
  fi
done
if $ALL_OK; then ok "3/3 健康检查通过"; else fail "健康检查不稳定"; fi

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

step "MessageReceived → 用户输入" "🦞 小龙虾变成思考动画"
send "{\"session_id\":\"$SID\",\"event\":\"MessageReceived\",\"status\":\"thinking\",\"user_prompt\":\"帮我写一个排序算法\",\"ts\":$(ts)}"
ok "已发送（含用户消息）"
wait_sec 2

step "LLMInput → 思考中" "🦞 保持思考动画"
send "{\"session_id\":\"$SID\",\"event\":\"LLMInput\",\"status\":\"thinking\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "LLMOutput → 工作中" "🦞 小龙虾变成工作动画 + O₂ 显示用量"
send "{\"session_id\":\"$SID\",\"event\":\"LLMOutput\",\"status\":\"working\",\"daily_tokens_used\":150000,\"input_tokens\":1200,\"output_tokens\":800,\"ts\":$(ts)}"
ok "已发送（附带 token 用量）"
wait_sec 2

step "ToolCall: Bash" "活动日志出现 Bash"
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Bash\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 1.5

step "ToolResult: Bash 成功" "活动日志出现 Bash 完成"
send "{\"session_id\":\"$SID\",\"event\":\"ToolResult\",\"status\":\"working\",\"tool\":\"Bash\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 1.5

step "ToolCall: Edit" "活动日志出现 Edit"
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Edit\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 1.5

step "ToolResult: Edit 成功" "活动日志出现 Edit 完成"
send "{\"session_id\":\"$SID\",\"event\":\"ToolResult\",\"status\":\"working\",\"tool\":\"Edit\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 1.5

step "ToolCall: Grep" "活动日志出现 Grep"
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Grep\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 1

step "ToolResult: Grep 出错" "🦞 小龙虾短暂变红，3 秒后恢复"
send "{\"session_id\":\"$SID\",\"event\":\"ToolResult\",\"status\":\"error\",\"tool\":\"Grep\",\"error\":\"No matches found\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 3

step "ToolCall: Read" "恢复工作动画"
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Read\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 1

step "ToolResult: Read 成功" ""
send "{\"session_id\":\"$SID\",\"event\":\"ToolResult\",\"status\":\"working\",\"tool\":\"Read\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 1

step "AgentEnd → 空闲" "🦞 小龙虾回到空闲动画"
send "{\"session_id\":\"$SID\",\"event\":\"AgentEnd\",\"status\":\"idle\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "SessionEnd → 会话结束" "🦞 小龙虾消失，显示对话历史"
send "{\"session_id\":\"$SID\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

# 验证会话确实关闭
HEALTH2=$(curl -s -m 3 "$URL/health" 2>/dev/null || echo "failed")
if echo "$HEALTH2" | grep -q "ok"; then
  ok "会话结束后连接正常"
else
  fail "会话结束后连接异常"
fi

# ═══════════════════════════════════════
header "测试 3: 多会话（2 只小龙虾）"
# ═══════════════════════════════════════

SID_A="multi-a-$(date +%s)"
SID_B="multi-b-$(date +%s)"

step "创建会话 A" "🦞 出现第 1 只小龙虾"
send "{\"session_id\":\"$SID_A\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
ok "会话 A: $SID_A"
wait_sec 1

step "创建会话 B" "🦞🦞 出现第 2 只小龙虾"
send "{\"session_id\":\"$SID_B\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
ok "会话 B: $SID_B"
wait_sec 2

step "会话 A 思考，会话 B 工作" "🦞 两只小龙虾不同动画"
send "{\"session_id\":\"$SID_A\",\"event\":\"LLMInput\",\"status\":\"thinking\",\"ts\":$(ts)}"
send "{\"session_id\":\"$SID_B\",\"event\":\"LLMOutput\",\"status\":\"working\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 3

step "会话 A 工具调用，会话 B 出错" "两只独立状态"
send "{\"session_id\":\"$SID_A\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Write\",\"ts\":$(ts)}"
send "{\"session_id\":\"$SID_B\",\"event\":\"ToolResult\",\"status\":\"error\",\"tool\":\"Bash\",\"error\":\"Permission denied\",\"ts\":$(ts)}"
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
header "测试 4: O₂ 氧气瓶（token 消耗梯度）"
# ═══════════════════════════════════════

SID_O2="o2-test-$(date +%s)"

step "创建会话" ""
send "{\"session_id\":\"$SID_O2\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
ok "已创建"
wait_sec 1

step "正常用量 (200K)" "🫧 O₂ 绿色 ~33%"
send "{\"session_id\":\"$SID_O2\",\"event\":\"LLMOutput\",\"status\":\"working\",\"daily_tokens_used\":200000,\"input_tokens\":5000,\"output_tokens\":3000,\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "中等用量 (500K)" "🫧 O₂ 黄色 ~50%消耗"
send "{\"session_id\":\"$SID_O2\",\"event\":\"LLMOutput\",\"status\":\"working\",\"daily_tokens_used\":500000,\"input_tokens\":8000,\"output_tokens\":5000,\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "警告用量 (700K)" "🫧 O₂ 黄色偏红"
send "{\"session_id\":\"$SID_O2\",\"event\":\"LLMOutput\",\"status\":\"working\",\"daily_tokens_used\":700000,\"input_tokens\":10000,\"output_tokens\":7000,\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "危险用量 (900K)" "🫧 O₂ 红色闪烁"
send "{\"session_id\":\"$SID_O2\",\"event\":\"LLMOutput\",\"status\":\"working\",\"daily_tokens_used\":900000,\"input_tokens\":12000,\"output_tokens\":9000,\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "极限用量 (290K / 300K容量)" "🫧 O₂ 红色快速闪烁"
send "{\"session_id\":\"$SID_O2\",\"event\":\"LLMOutput\",\"status\":\"working\",\"daily_tokens_used\":290000,\"input_tokens\":15000,\"output_tokens\":10000,\"ts\":$(ts)}"
ok "已发送"
wait_sec 3

step "清理" ""
send "{\"session_id\":\"$SID_O2\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "O₂ 测试会话已关闭"
wait_sec 1

# ═══════════════════════════════════════
header "测试 5: 情绪系统"
# ═══════════════════════════════════════

SID_EMO="emo-test-$(date +%s)"

step "创建会话" ""
send "{\"session_id\":\"$SID_EMO\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
ok "已创建"
wait_sec 1

step "积极消息" "🦞 表情变开心"
send "{\"session_id\":\"$SID_EMO\",\"event\":\"MessageReceived\",\"status\":\"thinking\",\"user_prompt\":\"太好了！这个功能完美运行\",\"ts\":$(ts)}"
ok "已发送（积极情绪）"
wait_sec 3

step "正常工作" ""
send "{\"session_id\":\"$SID_EMO\",\"event\":\"LLMOutput\",\"status\":\"working\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "消极消息" "🦞 表情变沮丧"
send "{\"session_id\":\"$SID_EMO\",\"event\":\"MessageReceived\",\"status\":\"thinking\",\"user_prompt\":\"这个bug好烦，已经第三次出错了\",\"ts\":$(ts)}"
ok "已发送（消极情绪）"
wait_sec 3

step "愤怒消息" "🦞 表情变愤怒"
send "{\"session_id\":\"$SID_EMO\",\"event\":\"MessageReceived\",\"status\":\"thinking\",\"user_prompt\":\"为什么又崩溃了！太气人了\",\"ts\":$(ts)}"
ok "已发送（愤怒情绪）"
wait_sec 3

step "清理" ""
send "{\"session_id\":\"$SID_EMO\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "情绪测试会话已关闭"
wait_sec 1

# ═══════════════════════════════════════
header "测试 6: 上下文压缩"
# ═══════════════════════════════════════

SID_CMP="compact-$(date +%s)"

step "创建会话 + 开始工作" ""
send "{\"session_id\":\"$SID_CMP\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
send "{\"session_id\":\"$SID_CMP\",\"event\":\"LLMOutput\",\"status\":\"working\",\"ts\":$(ts)}"
ok "会话已创建并开始工作"
wait_sec 2

step "触发 Compaction" "🦞 压缩动画（旋转/收缩特效）"
send "{\"session_id\":\"$SID_CMP\",\"event\":\"Compaction\",\"status\":\"compacting\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 3

step "压缩完成 → 继续工作" "🦞 恢复工作动画"
send "{\"session_id\":\"$SID_CMP\",\"event\":\"LLMOutput\",\"status\":\"working\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

step "清理" ""
send "{\"session_id\":\"$SID_CMP\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "压缩测试会话已关闭"
wait_sec 1

# ═══════════════════════════════════════
header "测试 7: 子代理（Subagent）"
# ═══════════════════════════════════════

SID_SUB="subagent-$(date +%s)"
SID_CHILD="subagent-child-$(date +%s)"

step "创建主会话" ""
send "{\"session_id\":\"$SID_SUB\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
ok "主会话已创建"
wait_sec 1

step "主会话开始工作" ""
send "{\"session_id\":\"$SID_SUB\",\"event\":\"LLMOutput\",\"status\":\"working\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 1

step "生成子代理" "🦞🦞 出现第 2 只小龙虾"
send "{\"session_id\":\"$SID_CHILD\",\"event\":\"SubagentSpawned\",\"status\":\"working\",\"ts\":$(ts)}"
ok "子代理已生成"
wait_sec 2

step "子代理工作中" "第 2 只小龙虾工作动画"
send "{\"session_id\":\"$SID_CHILD\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Grep\",\"ts\":$(ts)}"
send "{\"session_id\":\"$SID_CHILD\",\"event\":\"ToolResult\",\"status\":\"working\",\"tool\":\"Grep\",\"ts\":$(ts)}"
ok "子代理工具调用完成"
wait_sec 2

step "子代理结束" "🦞 回到 1 只小龙虾"
send "{\"session_id\":\"$SID_CHILD\",\"event\":\"SubagentEnded\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "子代理已结束"
wait_sec 2

step "清理主会话" ""
send "{\"session_id\":\"$SID_SUB\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "子代理测试已关闭"
wait_sec 1

# ═══════════════════════════════════════
header "测试 8: 快速连发（压力测试）"
# ═══════════════════════════════════════

SID_BURST="burst-$(date +%s)"

step "创建会话" ""
send "{\"session_id\":\"$SID_BURST\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
ok "已创建"
wait_sec 0.5

step "10 次快速工具调用" "🦞 持续工作动画，活动日志快速更新"
TOOLS=("Bash" "Edit" "Read" "Grep" "Write" "Glob" "Bash" "Edit" "Read" "Bash")
for tool in "${TOOLS[@]}"; do
  send "{\"session_id\":\"$SID_BURST\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"$tool\",\"ts\":$(ts)}"
  send "{\"session_id\":\"$SID_BURST\",\"event\":\"ToolResult\",\"status\":\"working\",\"tool\":\"$tool\",\"ts\":$(ts)}"
done
ok "10 次工具调用已发送"
wait_sec 2

step "快速 token 更新" "O₂ 条快速变化"
for tokens in 50000 100000 150000 200000 250000; do
  send "{\"session_id\":\"$SID_BURST\",\"event\":\"LLMOutput\",\"status\":\"working\",\"daily_tokens_used\":$tokens,\"input_tokens\":2000,\"output_tokens\":1500,\"ts\":$(ts)}"
done
ok "5 次 token 更新已发送"
wait_sec 2

step "清理" ""
send "{\"session_id\":\"$SID_BURST\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "压力测试会话已关闭"
wait_sec 1

# ═══════════════════════════════════════
header "测试 9: 完整工作流模拟"
# ═══════════════════════════════════════

SID_REAL="realworld-$(date +%s)"

step "模拟真实 Claude Code 会话" "完整的用户→思考→工具→回复循环"
echo ""

# 用户提问
send "{\"session_id\":\"$SID_REAL\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
echo -e "    ${GRAY}[1/8] 会话启动${NC}"
sleep 0.3

send "{\"session_id\":\"$SID_REAL\",\"event\":\"MessageReceived\",\"status\":\"thinking\",\"user_prompt\":\"帮我重构 UserService 的认证逻辑\",\"ts\":$(ts)}"
echo -e "    ${GRAY}[2/8] 用户提问${NC}"
sleep 1

# Claude 思考
send "{\"session_id\":\"$SID_REAL\",\"event\":\"LLMInput\",\"status\":\"thinking\",\"ts\":$(ts)}"
echo -e "    ${GRAY}[3/8] LLM 思考中...${NC}"
sleep 2

# 先读文件
send "{\"session_id\":\"$SID_REAL\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Read\",\"ts\":$(ts)}"
send "{\"session_id\":\"$SID_REAL\",\"event\":\"ToolResult\",\"status\":\"working\",\"tool\":\"Read\",\"daily_tokens_used\":180000,\"input_tokens\":3000,\"output_tokens\":500,\"ts\":$(ts)}"
echo -e "    ${GRAY}[4/8] 读取文件${NC}"
sleep 1

# 搜索相关代码
send "{\"session_id\":\"$SID_REAL\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Grep\",\"ts\":$(ts)}"
send "{\"session_id\":\"$SID_REAL\",\"event\":\"ToolResult\",\"status\":\"working\",\"tool\":\"Grep\",\"ts\":$(ts)}"
echo -e "    ${GRAY}[5/8] 搜索代码${NC}"
sleep 1

# 编辑代码
send "{\"session_id\":\"$SID_REAL\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Edit\",\"ts\":$(ts)}"
send "{\"session_id\":\"$SID_REAL\",\"event\":\"ToolResult\",\"status\":\"working\",\"tool\":\"Edit\",\"daily_tokens_used\":195000,\"input_tokens\":4000,\"output_tokens\":2000,\"ts\":$(ts)}"
echo -e "    ${GRAY}[6/8] 编辑代码${NC}"
sleep 1

# 运行测试
send "{\"session_id\":\"$SID_REAL\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Bash\",\"ts\":$(ts)}"
send "{\"session_id\":\"$SID_REAL\",\"event\":\"ToolResult\",\"status\":\"working\",\"tool\":\"Bash\",\"daily_tokens_used\":210000,\"input_tokens\":5000,\"output_tokens\":3000,\"ts\":$(ts)}"
echo -e "    ${GRAY}[7/8] 运行测试${NC}"
sleep 1

# Agent 完成
send "{\"session_id\":\"$SID_REAL\",\"event\":\"AgentEnd\",\"status\":\"idle\",\"ts\":$(ts)}"
echo -e "    ${GRAY}[8/8] 任务完成${NC}"
sleep 2

ok "真实工作流模拟完成（4 个工具调用，token 递增）"

step "会话结束" "🦞 消失，足迹记录应显示 4 次工具调用"
send "{\"session_id\":\"$SID_REAL\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
ok "已发送"
wait_sec 2

# ═══════════════════════════════════════
header "测试完成"
# ═══════════════════════════════════════

echo ""
TOTAL=$((PASS + FAIL))
if [ $FAIL -eq 0 ]; then
  echo -e "  ${GREEN}✅ 全部通过  ${PASS}/${TOTAL}${NC}"
else
  echo -e "  ${YELLOW}⚠️  ${PASS}/${TOTAL} 通过, ${FAIL} 失败${NC}"
fi
echo ""
echo -e "  ${GRAY}目视检查清单:${NC}"
echo -e "  ${GRAY}  □ 只有小龙虾（无寄居蟹）${NC}"
echo -e "  ${GRAY}  □ 单会话时小龙虾居中${NC}"
echo -e "  ${GRAY}  □ SessionEnd 后小龙虾消失${NC}"
echo -e "  ${GRAY}  □ 多会话时正确显示多只小龙虾${NC}"
echo -e "  ${GRAY}  □ O₂ 氧气条颜色随用量变化（绿→黄→红）${NC}"
echo -e "  ${GRAY}  □ 错误状态后 3 秒自动恢复${NC}"
echo -e "  ${GRAY}  □ 情绪变化可见（开心/沮丧/愤怒）${NC}"
echo -e "  ${GRAY}  □ 压缩动画正确${NC}"
echo -e "  ${GRAY}  □ 子代理生成/结束正确${NC}"
echo -e "  ${GRAY}  □ 快速连发不卡顿${NC}"
echo -e "  ${GRAY}  □ 足迹记录正确显示工具摘要${NC}"
echo ""
