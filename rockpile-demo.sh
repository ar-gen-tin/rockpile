#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Rockpile 产品演示脚本 — 适合录制推广视频
# ═══════════════════════════════════════════════════════════
#
# 用法:  bash rockpile-demo.sh [IP] [speed]
#
# 参数:
#   $1 = Rockpile 所在 Mac 的 IP（默认 127.0.0.1）
#   $2 = 速度倍数: 1=正常 0.5=慢放 2=快进（默认 1）
#
# 录制建议:
#   - 全屏终端 + Rockpile 刘海可见
#   - 展开刘海面板以显示 Dashboard
#   - 录屏工具: OBS / ScreenFlow / QuickTime
#   - 分辨率: 2560x1600 或 1920x1080
#   - 终端字体: 14pt+，深色背景

set -euo pipefail

HOST="${1:-127.0.0.1}"
SPEED="${2:-1}"
PORT=18790
URL="http://$HOST:$PORT"

# ── 颜色 ──
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
P='\033[0;35m'
NC='\033[0m'
B='\033[1m'
DIM='\033[2m'

# ── 全局 token 计数器（模拟真实消耗） ──
DAILY_USED=15000     # 起始：已用 15K（今天之前的用量）
INPUT_TOTAL=0
OUTPUT_TOTAL=0

# ── 速度控制 ──
pause() {
  local seconds
  seconds=$(echo "$1 / $SPEED" | bc -l)
  sleep "$seconds"
}

# ── 发送事件 ──
ts() { echo $(($(date +%s) * 1000)); }

send() {
  curl -s -m 5 -X POST \
    -H "Content-Type: application/json" \
    -d "$1" \
    "$URL" >/dev/null 2>&1 || true
  sleep 0.08
}

# 发送带 token 递增的事件
send_with_tokens() {
  local sid="$1" event="$2" status="$3"
  local in_tok="${4:-0}" out_tok="${5:-0}" extra="${6:-}"

  INPUT_TOTAL=$((INPUT_TOTAL + in_tok))
  OUTPUT_TOTAL=$((OUTPUT_TOTAL + out_tok))
  DAILY_USED=$((DAILY_USED + in_tok + out_tok))

  local json="{\"session_id\":\"$sid\",\"event\":\"$event\",\"status\":\"$status\""
  json="$json,\"input_tokens\":$in_tok,\"output_tokens\":$out_tok"
  json="$json,\"daily_tokens_used\":$DAILY_USED"
  json="$json,\"ts\":$(ts)"
  [ -n "$extra" ] && json="${json%\}},$extra}"
  json="$json}"

  send "$json"
}

# ── 显示 ──
scene() {
  echo ""
  echo ""
  echo -e "  ${B}${C}━━━ $1 ━━━${NC}"
  echo ""
  pause 1.5
}

narrate() {
  echo -e "  ${DIM}$1${NC}"
  pause 0.3
}

action() {
  echo -e "  ${G}▸${NC} $1"
}

o2_status() {
  local pct=$((100 - DAILY_USED * 100 / 300000))
  local color="$G"
  [ "$pct" -lt 60 ] && color="$Y"
  [ "$pct" -lt 30 ] && color="$R"
  echo -e "  ${DIM}O₂ ${color}${pct}%${NC} ${DIM}(${DAILY_USED}/${B}300K${NC}${DIM})${NC}"
}

# ── 检查连通性 ──
echo ""
echo -e "  ${B}${P}Rockpile${NC} ${DIM}— Product Demo${NC}"
echo ""

HEALTH=$(curl -s -m 3 "$URL/health" 2>/dev/null || echo "failed")
if ! echo "$HEALTH" | grep -q "ok"; then
  echo -e "  ${R}Rockpile 未启动或无法连接 ($URL)${NC}"
  exit 1
fi
echo -e "  ${G}▸${NC} 已连接 $URL"
echo -e "  ${DIM}Tank: 300K | 速度: ${SPEED}x${NC}"
pause 3

# ═══════════════════════════════════════════════════════════
# Scene 1: 小龙虾上线
# ═══════════════════════════════════════════════════════════

SID="demo-$(date +%s)"

scene "Scene 1  ·  小龙虾上线"

narrate "Claude Code 启动了一个新会话..."
pause 1.5

send "{\"session_id\":\"$SID\",\"event\":\"SessionStart\",\"status\":\"idle\",\"cwd\":\"/Users/dev/my-project\",\"ts\":$(ts)}"
action "会话已创建 — 小龙虾出现在刘海中"
o2_status

pause 5

# ═══════════════════════════════════════════════════════════
# Scene 2: 用户提问 → 思考
# ═══════════════════════════════════════════════════════════

scene "Scene 2  ·  用户提问"

narrate "用户: \"帮我重构 UserService 的认证模块\""
pause 1

send "{\"session_id\":\"$SID\",\"event\":\"MessageReceived\",\"status\":\"thinking\",\"user_prompt\":\"帮我重构 UserService 的认证模块\",\"ts\":$(ts)}"
action "小龙虾开始思考..."

pause 3.5

send_with_tokens "$SID" "LLMInput" "thinking" 800 0
narrate "正在分析代码结构，选择工具..."
o2_status

pause 3.5

# ═══════════════════════════════════════════════════════════
# Scene 3: 密集工具调用 — Dashboard 活动日志滚动
# ═══════════════════════════════════════════════════════════

scene "Scene 3  ·  AI 开始工作"

narrate "观察刘海面板 — 活动日志实时更新"
pause 2

# ── Read 1 ──
send_with_tokens "$SID" "LLMOutput" "working" 2500 1200
pause 0.3
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Read\",\"ts\":$(ts)}"
action "Read  UserService.swift"
pause 2

send_with_tokens "$SID" "ToolResult" "working" 4500 300 "\"tool\":\"Read\""
narrate "已读取 248 行"
o2_status
pause 1.5

# ── Grep 1 ──
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Grep\",\"ts\":$(ts)}"
action "Grep  \"authenticate\" across project"
pause 2

send_with_tokens "$SID" "ToolResult" "working" 1800 600 "\"tool\":\"Grep\""
narrate "找到 12 处引用"
o2_status
pause 1.5

# ── Read 2 ──
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Read\",\"ts\":$(ts)}"
action "Read  AuthToken.swift"
pause 1.5

send_with_tokens "$SID" "ToolResult" "working" 3200 200 "\"tool\":\"Read\""
narrate "已读取 86 行"
pause 1

# ── Read 3 ──
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Read\",\"ts\":$(ts)}"
action "Read  AuthMiddleware.swift"
pause 1.5

send_with_tokens "$SID" "ToolResult" "working" 2800 150 "\"tool\":\"Read\""
narrate "已读取 62 行"
o2_status
pause 1

# ── 思考一下 ──
send_with_tokens "$SID" "LLMOutput" "working" 3000 2800
narrate "分析完毕，开始重构..."
pause 2

# ── Edit 1 ──
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Edit\",\"ts\":$(ts)}"
action "Edit  UserService.swift — 重构 authenticate()"
pause 3

send_with_tokens "$SID" "ToolResult" "working" 1500 3500 "\"tool\":\"Edit\""
narrate "修改了 authenticate() 方法"
o2_status
pause 1.5

# ── Edit 2 ──
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Edit\",\"ts\":$(ts)}"
action "Edit  UserService.swift — 新增 verifyJWT()"
pause 2.5

send_with_tokens "$SID" "ToolResult" "working" 1200 2800 "\"tool\":\"Edit\""
narrate "新增 JWT 验证方法"
pause 1

# ── Edit 3 ──
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Edit\",\"ts\":$(ts)}"
action "Edit  AuthMiddleware.swift — 更新中间件"
pause 2.5

send_with_tokens "$SID" "ToolResult" "working" 1000 2200 "\"tool\":\"Edit\""
narrate "中间件已适配新接口"
o2_status
pause 1.5

# ── Write ──
send_with_tokens "$SID" "LLMOutput" "working" 2000 3600
pause 0.3
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Write\",\"ts\":$(ts)}"
action "Write  UserServiceTests.swift — 生成测试用例"
pause 3

send_with_tokens "$SID" "ToolResult" "working" 800 4200 "\"tool\":\"Write\""
narrate "已生成 8 个测试用例"
o2_status

pause 3

# ═══════════════════════════════════════════════════════════
# Scene 4: 遇到错误 → 自动恢复
# ═══════════════════════════════════════════════════════════

scene "Scene 4  ·  遇到错误"

narrate "运行测试..."
send_with_tokens "$SID" "LLMOutput" "working" 1500 1000
pause 0.3
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Bash\",\"ts\":$(ts)}"
action "Bash  swift test"
pause 3

send "{\"session_id\":\"$SID\",\"event\":\"ToolResult\",\"status\":\"error\",\"tool\":\"Bash\",\"error\":\"Type 'AuthToken' has no member 'isExpired'\",\"daily_tokens_used\":$DAILY_USED,\"ts\":$(ts)}"
action "${R}Error${NC}  编译失败 — 缺少 isExpired 属性"
narrate "小龙虾短暂变红..."

pause 4.5

narrate "AI 分析错误原因，自动修复..."
send_with_tokens "$SID" "LLMOutput" "working" 2000 1500
pause 0.5

send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Edit\",\"ts\":$(ts)}"
action "Edit  AuthToken.swift — 添加 isExpired 计算属性"
pause 2.5

send_with_tokens "$SID" "ToolResult" "working" 800 1800 "\"tool\":\"Edit\""
o2_status
pause 1

narrate "重新运行测试..."
send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Bash\",\"ts\":$(ts)}"
action "Bash  swift test"
pause 3

send_with_tokens "$SID" "ToolResult" "working" 600 400 "\"tool\":\"Bash\""
action "${G}All 8 tests passed${NC}"
o2_status

pause 4

# ═══════════════════════════════════════════════════════════
# Scene 5: O₂ 极限消耗 — 从当前一路飙到红色
# ═══════════════════════════════════════════════════════════

scene "Scene 5  ·  O₂ 氧气系统"

narrate "继续高强度工作，token 持续消耗..."
pause 2

# 快速消耗一波 token 到黄色区域
narrate "模拟大量 token 消耗..."
pause 1

# 快速几轮大量 token — 推到 60% 区域
for i in 1 2 3 4 5; do
  send_with_tokens "$SID" "LLMOutput" "working" 12000 8000
  send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Edit\",\"ts\":$(ts)}"
  send_with_tokens "$SID" "ToolResult" "working" 3000 5000 "\"tool\":\"Edit\""
  o2_status
  pause 1.5
done

narrate "O₂ 开始变黄..."
pause 3

# 继续推到红色区域
for i in 1 2 3 4; do
  send_with_tokens "$SID" "LLMOutput" "working" 10000 7000
  send "{\"session_id\":\"$SID\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Bash\",\"ts\":$(ts)}"
  send_with_tokens "$SID" "ToolResult" "working" 2000 4000 "\"tool\":\"Bash\""
  o2_status
  pause 1.5
done

narrate "O₂ 进入红色危险区!"
pause 3

# 最后几轮推到接近 K.O.
for i in 1 2; do
  send_with_tokens "$SID" "LLMOutput" "working" 8000 5000
  o2_status
  pause 2
done

narrate "小龙虾氧气快耗尽了... 红色闪烁!"
o2_status

pause 6

# 次日重置
DAILY_USED=20000
send_with_tokens "$SID" "LLMOutput" "working" 1000 500
narrate "(模拟次日重置)"
o2_status

pause 3

# ═══════════════════════════════════════════════════════════
# Scene 6: 情绪反应
# ═══════════════════════════════════════════════════════════

scene "Scene 6  ·  情绪感知"

narrate "小龙虾能感受到用户的情绪..."
pause 2

send "{\"session_id\":\"$SID\",\"event\":\"AgentEnd\",\"status\":\"idle\",\"ts\":$(ts)}"
pause 0.5

send "{\"session_id\":\"$SID\",\"event\":\"MessageReceived\",\"status\":\"thinking\",\"user_prompt\":\"太棒了！重构得很完美，测试全过了！谢谢\",\"ts\":$(ts)}"
action "用户: \"太棒了！重构得很完美!\""
narrate "小龙虾变开心了 :)"

pause 5

send_with_tokens "$SID" "LLMOutput" "working" 1000 800
send "{\"session_id\":\"$SID\",\"event\":\"AgentEnd\",\"status\":\"idle\",\"ts\":$(ts)}"
pause 1.5

send "{\"session_id\":\"$SID\",\"event\":\"MessageReceived\",\"status\":\"thinking\",\"user_prompt\":\"等等，这个 API 好像有问题，怎么又出 bug 了...\",\"ts\":$(ts)}"
action "用户: \"怎么又出 bug 了...\""
narrate "小龙虾变沮丧了"

pause 5

send_with_tokens "$SID" "LLMOutput" "working" 800 600
send "{\"session_id\":\"$SID\",\"event\":\"AgentEnd\",\"status\":\"idle\",\"ts\":$(ts)}"
pause 1.5

send "{\"session_id\":\"$SID\",\"event\":\"MessageReceived\",\"status\":\"thinking\",\"user_prompt\":\"没事啦修好了，继续加油！你做得很好\",\"ts\":$(ts)}"
action "用户: \"没事，继续加油！\""
narrate "小龙虾恢复精神了!"

pause 5

# ═══════════════════════════════════════════════════════════
# Scene 7: 多会话协作 — 两只小龙虾
# ═══════════════════════════════════════════════════════════

scene "Scene 7  ·  多任务并行"

send "{\"session_id\":\"$SID\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
pause 2.5

SID_A="demo-a-$(date +%s)"
SID_B="demo-b-$(date +%s)"

narrate "同时打开两个 Claude Code 终端..."
pause 1.5

send "{\"session_id\":\"$SID_A\",\"event\":\"SessionStart\",\"status\":\"idle\",\"cwd\":\"/Users/dev/backend\",\"ts\":$(ts)}"
action "Task A 上线 — 重构后端 API"
pause 2.5

send "{\"session_id\":\"$SID_B\",\"event\":\"SessionStart\",\"status\":\"idle\",\"cwd\":\"/Users/dev/frontend\",\"ts\":$(ts)}"
action "Task B 上线 — 编写前端组件"
narrate "池塘里出现两只小龙虾!"
pause 4

# A 思考，B 开始工作
send "{\"session_id\":\"$SID_A\",\"event\":\"MessageReceived\",\"status\":\"thinking\",\"user_prompt\":\"优化数据库查询性能\",\"ts\":$(ts)}"
action "Task A: 用户提问 — 优化数据库查询"
pause 1
send "{\"session_id\":\"$SID_A\",\"event\":\"LLMInput\",\"status\":\"thinking\",\"ts\":$(ts)}"

send "{\"session_id\":\"$SID_B\",\"event\":\"MessageReceived\",\"status\":\"thinking\",\"user_prompt\":\"创建登录表单组件\",\"ts\":$(ts)}"
action "Task B: 用户提问 — 创建登录表单"
pause 1

send_with_tokens "$SID_B" "LLMOutput" "working" 2000 1500
send "{\"session_id\":\"$SID_B\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Write\",\"ts\":$(ts)}"
action "Task B: Write  LoginForm.tsx"

pause 4

# A 也开始工作
send_with_tokens "$SID_A" "LLMOutput" "working" 3000 1200
send "{\"session_id\":\"$SID_A\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Read\",\"ts\":$(ts)}"
action "Task A: Read  queries.sql"

pause 3

send_with_tokens "$SID_A" "ToolResult" "working" 2500 200 "\"tool\":\"Read\""
send "{\"session_id\":\"$SID_A\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Edit\",\"ts\":$(ts)}"
action "Task A: Edit  UserRepository.py — 添加索引"

pause 3

narrate "两只小龙虾各忙各的，互不干扰"
pause 3

# B 完成
send_with_tokens "$SID_B" "ToolResult" "working" 500 3000 "\"tool\":\"Write\""
send "{\"session_id\":\"$SID_B\",\"event\":\"AgentEnd\",\"status\":\"idle\",\"ts\":$(ts)}"
pause 1.5
send "{\"session_id\":\"$SID_B\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
action "Task B 完成 — 一只小龙虾离场"

pause 4

# A 完成
send_with_tokens "$SID_A" "ToolResult" "working" 400 2000 "\"tool\":\"Edit\""
send "{\"session_id\":\"$SID_A\",\"event\":\"AgentEnd\",\"status\":\"idle\",\"ts\":$(ts)}"
pause 1.5
send "{\"session_id\":\"$SID_A\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"
action "Task A 完成 — 池塘安静下来"

pause 4

# ═══════════════════════════════════════════════════════════
# Scene 8: 上下文压缩
# ═══════════════════════════════════════════════════════════

SID_CMP="demo-cmp-$(date +%s)"

scene "Scene 8  ·  上下文压缩"

send "{\"session_id\":\"$SID_CMP\",\"event\":\"SessionStart\",\"status\":\"idle\",\"ts\":$(ts)}"
pause 1
send_with_tokens "$SID_CMP" "LLMOutput" "working" 2000 1500

# 模拟一段工作
send "{\"session_id\":\"$SID_CMP\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Read\",\"ts\":$(ts)}"
action "长会话工作中..."
pause 1
send_with_tokens "$SID_CMP" "ToolResult" "working" 3000 500 "\"tool\":\"Read\""
send "{\"session_id\":\"$SID_CMP\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Edit\",\"ts\":$(ts)}"
pause 1
send_with_tokens "$SID_CMP" "ToolResult" "working" 1000 2500 "\"tool\":\"Edit\""
send "{\"session_id\":\"$SID_CMP\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Bash\",\"ts\":$(ts)}"
pause 1
send_with_tokens "$SID_CMP" "ToolResult" "working" 500 300 "\"tool\":\"Bash\""

narrate "会话过长，Claude 自动压缩上下文..."
pause 3

send "{\"session_id\":\"$SID_CMP\",\"event\":\"Compaction\",\"status\":\"compacting\",\"ts\":$(ts)}"
action "Compaction — 观察小龙虾的压缩特效"

pause 6

send_with_tokens "$SID_CMP" "LLMOutput" "working" 1500 1000
narrate "压缩完成，继续工作"
pause 2

send "{\"session_id\":\"$SID_CMP\",\"event\":\"ToolCall\",\"status\":\"working\",\"tool\":\"Edit\",\"ts\":$(ts)}"
pause 1.5
send_with_tokens "$SID_CMP" "ToolResult" "working" 800 1800 "\"tool\":\"Edit\""
narrate "工作恢复正常"
o2_status

pause 2

send "{\"session_id\":\"$SID_CMP\",\"event\":\"AgentEnd\",\"status\":\"idle\",\"ts\":$(ts)}"
pause 1.5
send "{\"session_id\":\"$SID_CMP\",\"event\":\"SessionEnd\",\"status\":\"ended\",\"ts\":$(ts)}"

pause 3

# ═══════════════════════════════════════════════════════════
# Finale
# ═══════════════════════════════════════════════════════════

echo ""
echo ""
echo -e "  ${B}${P}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${B}  Rockpile${NC}"
echo -e "  ${DIM}  Your AI Agent's Pixel Companion${NC}"
echo ""
echo -e "  ${DIM}  macOS Notch  ·  Real-time  ·  Open Source${NC}"
echo ""
echo -e "  ${B}${P}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

o2_status
echo -e "  ${DIM}Total tokens: ${INPUT_TOTAL} in + ${OUTPUT_TOTAL} out${NC}"
echo ""
pause 8
