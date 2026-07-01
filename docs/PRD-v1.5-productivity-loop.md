# Rockpile v1.5 PRD - 生产力闭环

> 从"只读"监控器 → "读写"效率入口

---

## 阶段规划总览

| 阶段 | 目标 | 优先级 | 版本 |
|------|------|--------|------|
| 一：生产力闭环 | 快捷指令 + 拖拽 + 急停 | ⭐⭐⭐⭐⭐ | v1.1 - v1.5 |
| 二：深度养成 | 成就系统 + 经验值 + 皮肤 | ⭐⭐⭐⭐ | v2.0 |
| 三：生态破圈 | 开放 API + 多模型 + 硬件联动 | ⭐⭐⭐ | v2.5 |
| 四：轻量社交 | 局域网串门 + 团队排行 | ⭐⭐ | v3.0 |

---

## 阶段一：核心功能规格

### 1. 快捷指令舱 (Notch Spotlight)

- 展开面板信息区底部增加半透明输入框
- 聚焦时小龙虾切换为"等待中"姿态
- Enter 发送，小龙虾切换为"工作中"
- 通过 Unix Socket / TCP 反向发送给 Rockpile

### 2. 拖拽喂食 (Drag & Drop)

- 支持拖拽文本/文件到 Notch 区域
- 靠近时触发水波纹效果
- 松手触发"喂食"动画
- 文本作为 Prompt，文件提取路径发送

### 3. 物理级急停 (Kill Switch)

- 双击小龙虾触发中断
- 屏幕碎裂特效 + 强制休眠
- 向 Rockpile 发送 Interrupt 信号
- O2 进度条立即冻结

---

## 通信架构升级

### 当前（单向）

```
Rockpile Hook → 插件 POST → Rockpile (18790/socket) 接收渲染
```

### 升级（双向）

```
Rockpile → POST → Rockpile 插件 (18791) → 执行动作
Rockpile Hook → 插件 POST → Rockpile (18790/socket) 接收渲染
```

### 反向指令 API 契约

#### 快捷输入 / 拖拽

```json
POST http://<Rockpile IP>:18791/command
{
  "action": "chat",
  "payload": {
    "message": "用户输入的文本",
    "attachments": ["/path/to/file"],
    "context_mode": "append"
  },
  "timestamp": 1715328492
}
```

#### 急停

```json
POST http://<Rockpile IP>:18791/command
{
  "action": "interrupt",
  "payload": {
    "reason": "user_force_stop",
    "halt_current_tool": true
  },
  "timestamp": 1715328500
}
```

---

## 插件改造要点

- index.js 新增本地 HTTP Server 监听 18791
- 路由处理: chat → sendUserMessage, interrupt → abort
- 双机模式需在 /register 时互换指令端口
- 死锁保护: process.kill() 作为终极兜底

---

## UI 变更清单

| 区域 | 变更前 | 变更后 |
|------|--------|--------|
| 池塘区 | 水下场景 + 精灵 | + 拖拽悬停水波纹/张嘴动画 |
| 信息区 | 状态 + O2 + 日志 | + 底部输入框 `[输入指令... (↵ 发送)]` |
| 交互 | 单击/双击/长按/右键 | + 双击急停 + 拖拽喂食 |

---

## 风险与对策

| 风险 | 对策 |
|------|------|
| 远程急停延迟 | 本地立即冻结 UI，异步重试 |
| 输入框焦点冲突 | NonactivatingPanel 不抢全局焦点 |
| Rockpile 主线程阻塞 | process.kill() 系统级兜底 |
