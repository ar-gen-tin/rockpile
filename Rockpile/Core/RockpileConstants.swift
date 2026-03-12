import Foundation

/// 应用级常量集中管理 — 消灭魔法数字 (CodexBar 风格)
///
/// 命名空间 `RC` 与设计系统 `DS` 对称。
/// 所有数值常量统一归入此处，文件内按子域分组。
enum RC {
    enum Session {
        /// 5 分钟无活动 → 进入睡眠
        static let sleepTimeout: TimeInterval = 300
    }

    enum Emotion {
        /// 情绪衰减周期（秒）
        static let decayInterval: TimeInterval = 60
    }

    enum Gateway {
        /// WebSocket ping 间隔
        static let pingInterval: TimeInterval = 30
        /// 请求超时
        static let requestTimeout: TimeInterval = 30
        /// 最大重连延迟
        static let maxReconnectDelay: TimeInterval = 30
        /// 待处理请求上限
        static let maxPendingRequests = 20
    }

    enum Feed {
        /// 喂食冷却（秒）
        static let cooldown: TimeInterval = 30
        /// 每次喂食恢复的 O₂ 比例
        static let bonusFraction: Double = 0.05
    }

    enum Panel {
        /// 展开面板尺寸
        static let expandedSize = CGSize(width: 450, height: 450)
        /// 展开面板水平内边距
        static let expandedHorizontalPadding: CGFloat = 19 * 2
    }

    enum BurnRate {
        /// 滑动窗口大小（秒）— 用于计算近期消耗率
        static let windowSize: TimeInterval = 120
        /// 最少数据点 — 低于此数不计算
        static let minDataPoints = 3
        /// 5 小时工作预算（分钟）— 配速基准
        static let dailyBudgetMinutes: Double = 300
        /// 速度趋势阈值 — ±15% 判定加速/减速
        static let velocityThreshold: Double = 0.15
    }

    enum Heartbeat {
        /// 心跳日志间隔（秒）
        static let interval: TimeInterval = 300
    }
}
