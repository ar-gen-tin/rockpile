import Foundation

/// AI 服务健康状态 — 基于 UpTo 的 StatusProvider 设计
enum HealthStatus: String, Sendable, Codable, Comparable {
    case operational
    case degraded
    case majorOutage
    case unknown

    static func < (lhs: HealthStatus, rhs: HealthStatus) -> Bool {
        lhs.severity < rhs.severity
    }

    var severity: Int {
        switch self {
        case .operational:  return 0
        case .unknown:      return 1
        case .degraded:     return 2
        case .majorOutage:  return 3
        }
    }

    @MainActor
    var displayName: String {
        switch self {
        case .operational:  return L10n.s("svcStatus.operational")
        case .degraded:     return L10n.s("svcStatus.degraded")
        case .majorOutage:  return L10n.s("svcStatus.majorOutage")
        case .unknown:      return L10n.s("svcStatus.unknown")
        }
    }

    var dotColor: String {
        switch self {
        case .operational:  return "green"
        case .degraded:     return "yellow"
        case .majorOutage:  return "red"
        case .unknown:      return "gray"
        }
    }
}

/// 组件级别状态
struct ComponentStatus: Sendable {
    let name: String
    let status: HealthStatus
}

/// 被监控的服务定义
struct MonitoredService: Identifiable, Sendable {
    let id: String
    let name: String
    let provider: String
}

/// 服务状态查询结果
struct ServiceStatusResult: Sendable, Identifiable {
    var id: String { service.id }
    let service: MonitoredService
    let status: HealthStatus
    let components: [ComponentStatus]
    let checkedAt: Date
}

/// 状态数据源抽象 — 每个 AI 服务实现一个
protocol StatusProvider: Sendable {
    var service: MonitoredService { get }
    func fetchStatus() async throws -> ServiceStatusResult
}
