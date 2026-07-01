# Rockpile 像素精灵重绘规范

## 一、总览

| 项目 | 旧版 | 新版 |
|------|------|------|
| 格式 | PNG sprite sheet | SVG sprite sheet (Aseprite → export) |
| 帧尺寸 | 64×64px | 48×48px |
| 网格 | 无约束 | **4px 严格网格** |
| 帧数 | 12帧/状态 (compacting 10) | **8帧/状态** (平衡流畅度与文件大小) |
| 情绪 | 4种 (neutral/happy/sad/angry) | **3种 (neutral/happy/sad)** |
| 生物 | 2 | 2 |
| 总文件数 | 41 PNG | **36 SVG** (6状态×3情绪×2生物) |

---

## 二、4px 网格系统

```
每个像素块 = 4×4px
画布 = 48×48px = 12×12 格
```

所有造型必须对齐 4px 网格。禁止 1px/2px 像素，保证 SVG 缩放时像素感一致。

### 色彩规则
- 每个生物最多 **6 色**（含高光和阴影）
- 眼睛颜色随状态变化（不换图，运行时叠色）
- 背景透明

---

## 三、寄居蟹 造型规范

### 轮廓特征：**圆矮型 — 壳为主体**

```
    ╭──╮         ← 触角 (2格高, 状态决定姿态)
   ●    ●        ← 眼睛 (1格, 颜色=状态)
  ┌──────┐
  │ 钳子  │      ← 钳子 (2格宽, 壳两侧)
  ├──────┤
  │      │
  │  壳  │       ← 壳体 (6格宽×4格高, 主体最大)
  │      │
  ├──┬──┬┤
  └┘ └┘ └┘       ← 腿 (3对, 1格宽)
```

### 色板 (6色)

| 角色 | HEX | 用途 |
|------|-----|------|
| shell-light | #E8C49A | 壳顶部/高光 |
| shell-mid | #D4A574 | 壳主体 |
| shell-dark | #B87A4B | 壳底部/阴影 |
| body | #C8956C | 身体/钳子 |
| leg | #8B5530 | 腿/触角 |
| eye-base | #111111 | 眼睛默认 |

### 眼睛状态色 (运行时覆盖)

| 状态 | 眼睛色 | 含义 |
|------|--------|------|
| idle | #111 (黑) | 正常 |
| working | #FFF (白) | 专注 |
| thinking | #06B6D4 (cyan) | 沉思 |
| sleeping | 闭合 (2×1px 线) | 休眠 |
| error | #EF4444 (红) | 警报 |
| dead | #444 (灰) + ×× 覆盖 | 死亡 |

### 6 状态帧动画要点

**idle (8帧):**
- 触角微摆 (±1格, 4帧一周期)
- 壳轻微上下呼吸 (整体偏移 0-1px)
- 钳子自然放下

**working (8帧):**
- 触角举高并快速摆动
- 钳子交替开合 (左开→右开→双开→收)
- 壳体轻颤

**thinking (8帧):**
- 触角内收贴头
- 一只钳子抬起托腮
- 壳体缓慢左右摇 (±1格)
- 思考气泡锚点: 右上角 (代码层叠加)

**sleeping (8帧):**
- 完全缩入壳中 (无触角/钳子/腿可见)
- 壳体微微起伏 (呼吸感, ±1px)
- zZ 锚点: 右上角

**error (8帧):**
- 触角外张 (惊慌)
- 钳子防御性举起
- 整体快速左右抖动 (±1格, 2帧一周期)
- 壳体颜色不变 (眼睛变红即可)

**dead (8帧):**
- 壳体灰化 (全部色值降饱和 50%)
- 缩壳至 0.7x 大小 (壳占满, 无肢体)
- 微弱左右摇晃 (慢, ±0.5格)
- ×× 眼覆盖

### 情绪变体差异

| 部位 | neutral | happy | sad |
|------|---------|-------|-----|
| 眼睛 | ● 圆 | ◡ 弯月 | ● 下垂 |
| 嘴 | 无 | ︶ 微笑线 | 无 |
| 触角 | 自然 | 上扬 | 下垂 |
| 整体 | 标准 | 微微上浮 1px | 微微下沉 1px |

---

## 四、小龙虾 造型规范

### 轮廓特征：**长尖型 — 钳子突出**

```
  ╲    ╱         ← 钳子 (3格高, 最醒目部位)
   ╲  ╱
    ●●           ← 眼睛 + 触须
  ┌────┐
  │ 头 │         ← 头胸甲 (4格宽)
  ├────┤
  │ 腹 │         ← 腹节 (3段递减)
  ├──┤
  │尾│           ← 尾扇 (2格宽)
  └──┘
  ╱╲ ╱╲          ← 游泳足 (2对)
```

### 色板 (6色)

| 角色 | HEX | 用途 |
|------|-----|------|
| claw | #EF4444 | 钳子/触须 |
| head-light | #F87171 | 头胸甲高光 |
| body | #DC2626 | 身体主色 |
| belly | #FCA5A5 | 腹部/亮面 |
| tail | #B91C1C | 尾部/暗色 |
| deep | #7F1D1D | 最深处/关节 |

### 眼睛状态色

同寄居蟹规范。

### 6 状态帧动画要点

**idle (8帧):**
- 钳子轻柔开合 (±1格)
- 尾部轻摆 (游泳感, ±1格)
- 触须微摆
- 游泳足缓慢划动

**working (8帧):**
- 钳子完全展开, 快速夹击
- 尾部有力弹动 (推进感)
- 整体前后微移 (±1格)

**thinking (8帧):**
- 钳子收拢抱胸
- 尾部卷曲
- 触须下垂
- 整体静止, 仅呼吸起伏

**sleeping (8帧):**
- 钳子收拢贴身
- 尾部完全卷曲 (虾卷造型)
- 整体扁平化 (高度缩减 2格)
- 微弱呼吸起伏

**error (8帧):**
- 钳子防御展开
- 尾部弹直 (惊吓反射)
- 触须竖起
- 快速后退抖动

**dead (8帧):**
- **翻肚** (flipY) — 标志性死亡姿态
- 全身灰化
- 钳子和腿僵硬伸展
- 缓慢下沉飘动

### 情绪变体差异

| 部位 | neutral | happy | sad |
|------|---------|-------|-----|
| 眼睛 | ● 圆 | ◡ 弯 | ● 下垂 |
| 钳子 | 自然开 | 举高 (欢呼) | 下垂 |
| 尾 | 自然伸 | 翘起 | 拖地 |
| 整体 | 标准 | 上浮 1px | 下沉 1px |

---

## 五、动画参数表

### 帧率

| 状态 | 寄居蟹 FPS | 小龙虾 FPS |
|------|-----------|-----------|
| idle | 2.0 | 3.0 |
| working | 3.5 | 5.0 |
| thinking | 2.5 | 3.0 |
| sleeping | 1.5 | 2.0 |
| error | 3.0 | 4.0 |
| dead | 1.0 | 1.0 |

### Bob/Wobble 参数 (代码层)

| 参数 | 寄居蟹 | 小龙虾 |
|------|--------|--------|
| bob amplitude | 0.8pt | 1.5pt |
| bob period | 3.0s | 1.5s |
| wobble | ±3° shell | 无 |
| swim range | ±15pt | ±25pt |
| crawl interval | 12-20s | 8-15s |

---

## 六、Aseprite 工作流

### 文件结构
```
sprites/
├── hermit_crab/
│   ├── crab_idle_neutral.ase       (8帧, 48×48)
│   ├── crab_idle_happy.ase
│   ├── crab_idle_sad.ase
│   ├── crab_working_neutral.ase
│   ├── crab_working_happy.ase
│   ├── crab_working_sad.ase
│   ├── crab_thinking_neutral.ase
│   ├── ... (共 18 文件)
│   └── crab_dead_neutral.ase
├── crawfish/
│   ├── crawfish_idle_neutral.ase
│   ├── ... (共 18 文件)
│   └── crawfish_dead_neutral.ase
└── README.md
```

### 导出命令
```bash
# 单个文件
aseprite -b --sheet-pack --trim --extrude 1 \
  --data output/crab_idle_neutral.json \
  --sheet output/crab_idle_neutral.svg \
  --format json-array \
  sprites/hermit_crab/crab_idle_neutral.ase

# 批量 (使用 scripts/export-sprites.sh)
./scripts/export-sprites.sh sprites/ Rockpile/Resources/Sprites/
```

### Aseprite 设置
- Canvas: 48×48px
- Color Mode: RGBA
- Grid: 4×4px (View → Grid → Grid Settings)
- Pixel Perfect: ON
- Onion Skin: 2 frames (前后各 1)

---

## 七、SVG 集成

### SpriteMetadata.swift 已支持
```swift
// 自动加载 JSON metadata
if let meta = SpriteMetadata.load(named: "crab_idle_neutral") {
    SpriteSheetView(
        spriteSheet: "crab_idle_neutral",
        metadata: meta  // JSON 驱动帧位置和时长
    )
}
```

### 回退机制
无 metadata 时回退到网格计算 (现有行为)：
```swift
SpriteSheetView(
    spriteSheet: "crab_idle_neutral",
    frameCount: 8,
    columns: 8,
    fps: 2.0
)
```

---

## 八、验收标准

1. **像素对齐**: 所有元素严格 4px 网格, 无亚像素
2. **帧流畅**: 8 帧循环无跳帧感
3. **辨识度**: 48pt 下蟹/虾轮廓一眼可分 (圆矮 vs 长尖)
4. **状态清晰**: 不看标签也能通过姿态判断状态
5. **缩放**: SVG 在 24pt(刘海)到 120pt(放大) 范围内均清晰
6. **情绪**: neutral/happy/sad 差异可感知但不夸张
7. **色板**: 每生物 ≤6 色, 无渐变
8. **文件大小**: 单个 SVG < 5KB
