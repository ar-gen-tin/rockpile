import Foundation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "AtlassianStatus")

/// Anthropic 服务状态 — 使用 Atlassian Statuspage API
///
/// API: https://status.anthropic.com/api/v2/summary.json
/// indicator 映射: none → operational, minor → degraded, major/critical → majorOutage
struct AtlassianStatusProvider: StatusProvider {
    let service: MonitoredService
    let statusPageURL: URL

    init(
        id: String = "anthropic",
        name: String = "Anthropic",
        provider: String = "Claude",
        url: String = "https://status.anthropic.com/api/v2/summary.json"
    ) {
        self.service = MonitoredService(id: id, name: name, provider: provider)
        self.statusPageURL = URL(string: url)!
    }

    func fetchStatus() async throws -> ServiceStatusResult {
        var request = URLRequest(url: statusPageURL)
        request.timeoutInterval = RC.ServiceStatus.requestTimeout

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StatusError.parseFailed
        }

        // Parse overall status
        let overallStatus: HealthStatus
        if let status = json["status"] as? [String: Any],
           let indicator = status["indicator"] as? String {
            overallStatus = mapIndicator(indicator)
        } else {
            overallStatus = .unknown
        }

        // Parse components
        var components: [ComponentStatus] = []
        if let comps = json["components"] as? [[String: Any]] {
            for comp in comps {
                guard let name = comp["name"] as? String,
                      let status = comp["status"] as? String else { continue }
                // Skip page-level component
                if name.lowercased().contains("all systems") { continue }
                components.append(ComponentStatus(
                    name: name,
                    status: mapComponentStatus(status)
                ))
            }
        }

        return ServiceStatusResult(
            service: service,
            status: overallStatus,
            components: components,
            checkedAt: Date()
        )
    }

    private func mapIndicator(_ indicator: String) -> HealthStatus {
        switch indicator.lowercased() {
        case "none":                return .operational
        case "minor":               return .degraded
        case "major", "critical":   return .majorOutage
        default:                    return .unknown
        }
    }

    private func mapComponentStatus(_ status: String) -> HealthStatus {
        switch status.lowercased() {
        case "operational":             return .operational
        case "degraded_performance":    return .degraded
        case "partial_outage":          return .degraded
        case "major_outage":            return .majorOutage
        default:                        return .unknown
        }
    }
}

enum StatusError: LocalizedError {
    case parseFailed
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .parseFailed: return "Status page parse failed"
        case .networkError(let msg): return msg
        }
    }
}
