import Foundation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "GoogleCloudStatus")

/// Google Cloud / Gemini 服务状态 — 使用 Google Cloud incidents JSON
///
/// API: https://status.cloud.google.com/incidents.json
/// 过滤 Gemini / Vertex AI 关键词，取最近事件判断健康状态
struct GoogleCloudStatusProvider: StatusProvider {
    let service: MonitoredService
    let statusURL: URL

    /// 过滤关键词 — 只关注 AI 相关服务
    private let relevantKeywords = ["gemini", "vertex ai", "ai platform", "generative ai"]

    init(
        id: String = "google",
        name: String = "Google AI",
        provider: String = "Gemini",
        url: String = "https://status.cloud.google.com/incidents.json"
    ) {
        self.service = MonitoredService(id: id, name: name, provider: provider)
        self.statusURL = URL(string: url)!
    }

    func fetchStatus() async throws -> ServiceStatusResult {
        var request = URLRequest(url: statusURL)
        request.timeoutInterval = RC.ServiceStatus.requestTimeout

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let incidents = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw StatusError.parseFailed
        }

        // Filter for AI-related incidents
        let aiIncidents = incidents.filter { incident in
            guard let affectedProducts = incident["affected_products"] as? [[String: Any]] else { return false }
            return affectedProducts.contains { product in
                guard let title = product["title"] as? String else { return false }
                let lower = title.lowercased()
                return relevantKeywords.contains { lower.contains($0) }
            }
        }

        // Check if any recent (within 48h) active incidents
        let recentIncidents = aiIncidents.filter { incident in
            // Check if incident is still active (no end time)
            if let end = incident["end"] as? String, !end.isEmpty { return false }

            // Check if recent
            if let created = incident["created"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: created) {
                    return Date().timeIntervalSince(date) < 172800 // 48h
                }
            }
            return true
        }

        let status: HealthStatus
        if recentIncidents.isEmpty {
            status = .operational
        } else {
            // Check severity
            let hasMajor = recentIncidents.contains { incident in
                let severity = (incident["severity"] as? String)?.lowercased() ?? ""
                return severity == "high" || severity == "critical"
            }
            status = hasMajor ? .majorOutage : .degraded
        }

        return ServiceStatusResult(
            service: service,
            status: status,
            components: [],
            checkedAt: Date()
        )
    }
}
