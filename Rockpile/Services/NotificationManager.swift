import Foundation
import UserNotifications
import Observation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "NotificationManager")

/// O₂ 区域 — 用于判断是否跨越阈值
enum O2Zone: Equatable, Sendable {
    case normal
    case low
    case critical
}

/// 桌面通知管理 — 基于 UpTo 的通知系统设计
///
/// 4 类通知：
/// 1. 状态变化 (idle → working → error)
/// 2. O₂ 阈值 (跨越 30% / 10%)
/// 3. 连接变化 (Gateway 连接/断开)
/// 4. 会话完成 (SessionEnd)
///
/// 每类通知有独立冷却和去重逻辑。
@MainActor
@Observable
final class NotificationManager {
    static let shared = NotificationManager()

    /// 权限状态
    private(set) var isAuthorized = false

    /// 上一次各类通知的发送时间 — 冷却判定
    private var lastNotificationTimes: [String: Date] = [:]

    /// 上一次各 task 状态 — 防重复
    private var previousTaskStates: [String: ClawTask] = [:]

    /// 上一次各 creature 的 O₂ 区域 — 跨阈值才触发
    private var previousO2Zones: [CreatureType: O2Zone] = [:]

    private init() {
        requestPermission()
    }

    // MARK: - Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            Task { @MainActor in
                self.isAuthorized = granted
                if let error {
                    logger.warning("Notification permission error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - State Change Notification

    func notifyStateChange(sessionId: String, creatureType: CreatureType, newTask: ClawTask) {
        guard AppSettings.notificationsEnabled, AppSettings.notifyStateChange else { return }

        let previousTask = previousTaskStates[sessionId]
        previousTaskStates[sessionId] = newTask

        // Only notify on significant transitions
        guard let previous = previousTask, previous != newTask else { return }
        // Only notify error transitions
        guard newTask == .error else { return }

        let key = "state.\(sessionId)"
        guard !isCoolingDown(key) else { return }
        markSent(key)

        let title = "Rockpile"
        let body = L10n.s("notify.stateChanged")
            .replacingOccurrences(of: "{creature}", with: L10n.s(creatureType.displayNameKey))
            .replacingOccurrences(of: "{state}", with: newTask.displayName)

        send(id: "state-\(sessionId)", title: title, body: body)
    }

    // MARK: - O₂ Threshold Notification

    func checkO2Thresholds(creatureType: CreatureType, oxygenPercent: Double) {
        guard AppSettings.notificationsEnabled else { return }

        let currentZone: O2Zone
        if oxygenPercent <= RC.Notification.criticalO2Threshold {
            currentZone = .critical
        } else if oxygenPercent <= RC.Notification.lowO2Threshold {
            currentZone = .low
        } else {
            currentZone = .normal
        }

        let previousZone = previousO2Zones[creatureType] ?? .normal
        previousO2Zones[creatureType] = currentZone

        // Only notify when crossing into a worse zone
        guard currentZone != previousZone else { return }

        let percentStr = String(format: "%.0f", oxygenPercent * 100)
        let creatureName = L10n.s(creatureType.displayNameKey)

        if currentZone == .critical && AppSettings.notifyO2Critical {
            let key = "o2critical.\(creatureType.rawValue)"
            guard !isCoolingDown(key) else { return }
            markSent(key)

            let body = L10n.s("notify.o2CriticalBody")
                .replacingOccurrences(of: "{creature}", with: creatureName)
                .replacingOccurrences(of: "{percent}", with: percentStr)
            send(id: "o2-\(creatureType.rawValue)", title: "Rockpile", body: body, sound: .defaultCritical)
        } else if currentZone == .low && AppSettings.notifyO2Low {
            let key = "o2low.\(creatureType.rawValue)"
            guard !isCoolingDown(key) else { return }
            markSent(key)

            let body = L10n.s("notify.o2LowBody")
                .replacingOccurrences(of: "{creature}", with: creatureName)
                .replacingOccurrences(of: "{percent}", with: percentStr)
            send(id: "o2-\(creatureType.rawValue)", title: "Rockpile", body: body)
        }
    }

    // MARK: - Connection Change Notification

    func notifyConnectionChange(type: String, connected: Bool) {
        guard AppSettings.notificationsEnabled, AppSettings.notifyConnection else { return }

        let key = "conn.\(type)"
        guard !isCoolingDown(key) else { return }
        markSent(key)

        let bodyKey = connected ? "notify.connected" : "notify.disconnected"
        let body = L10n.s(bodyKey).replacingOccurrences(of: "{type}", with: type)

        send(id: "conn-\(type)", title: "Rockpile", body: body)
    }

    // MARK: - Session Complete Notification

    func notifySessionComplete(session: SessionData) {
        guard AppSettings.notificationsEnabled, AppSettings.notifySessionComplete else { return }

        let key = "session.\(session.id)"
        guard !isCoolingDown(key) else { return }
        markSent(key)

        let tokens = TokenTracker.formatTokens(session.tokenTracker.sessionTotalTokens)
        let body = L10n.s("notify.sessionDone")
            .replacingOccurrences(of: "{tokens}", with: tokens)

        send(id: "session-\(session.id)", title: "Rockpile", body: body)
    }

    // MARK: - Service Status Notification

    func notifyServiceStatusChange(serviceName: String, status: String) {
        guard AppSettings.notificationsEnabled, AppSettings.notifyServiceStatus else { return }

        let key = "svcStatus.\(serviceName)"
        guard !isCoolingDown(key) else { return }
        markSent(key)

        send(id: "svc-\(serviceName)", title: "Rockpile · \(serviceName)", body: status)
    }

    // MARK: - Cooldown

    private func isCoolingDown(_ key: String) -> Bool {
        guard let lastTime = lastNotificationTimes[key] else { return false }
        return Date().timeIntervalSince(lastTime) < RC.Notification.cooldownSeconds
    }

    private func markSent(_ key: String) {
        lastNotificationTimes[key] = Date()
    }

    // MARK: - Send

    private func send(id: String, title: String, body: String, sound: UNNotificationSound = .default) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.warning("Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    /// 清理已结束会话的状态缓存
    func cleanupSession(_ sessionId: String) {
        previousTaskStates.removeValue(forKey: sessionId)
    }
}
