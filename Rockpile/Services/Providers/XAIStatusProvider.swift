import Foundation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "XAIStatus")

/// xAI 服务状态 — 使用 RSS feed 解析
///
/// Feed URL: https://status.x.ai/history.rss
/// 解析最新 item 的 category 关键词映射到 HealthStatus
struct XAIStatusProvider: StatusProvider {
    let service: MonitoredService
    let feedURL: URL

    init(
        id: String = "xai",
        name: String = "xAI",
        provider: String = "Grok",
        url: String = "https://status.x.ai/history.rss"
    ) {
        self.service = MonitoredService(id: id, name: name, provider: provider)
        self.feedURL = URL(string: url)!
    }

    func fetchStatus() async throws -> ServiceStatusResult {
        var request = URLRequest(url: feedURL)
        request.timeoutInterval = RC.ServiceStatus.requestTimeout

        let (data, _) = try await URLSession.shared.data(for: request)

        let parser = RSSStatusParser(data: data)
        let items = parser.parse()

        // If no recent incidents, assume operational
        guard let latest = items.first else {
            return ServiceStatusResult(
                service: service,
                status: .operational,
                components: [],
                checkedAt: Date()
            )
        }

        // Check if the latest incident is recent (within 24h)
        let isRecent = latest.pubDate.map { Date().timeIntervalSince($0) < 86400 } ?? true
        let status: HealthStatus = isRecent ? mapCategory(latest.category) : .operational

        return ServiceStatusResult(
            service: service,
            status: status,
            components: [],
            checkedAt: Date()
        )
    }

    private func mapCategory(_ category: String) -> HealthStatus {
        let lower = category.lowercased()
        if lower.contains("major") || lower.contains("outage") || lower.contains("critical") {
            return .majorOutage
        }
        if lower.contains("degraded") || lower.contains("minor") || lower.contains("partial") {
            return .degraded
        }
        if lower.contains("resolved") || lower.contains("completed") || lower.contains("operational") {
            return .operational
        }
        return .degraded
    }
}

// MARK: - RSS Parser

private struct RSSItem {
    let title: String
    let category: String
    let pubDate: Date?
}

private final class RSSStatusParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var items: [RSSItem] = []
    private var currentElement = ""
    private var currentTitle = ""
    private var currentCategory = ""
    private var currentPubDate = ""
    private var insideItem = false

    init(data: Data) {
        self.data = data
    }

    func parse() -> [RSSItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentCategory = ""
            currentPubDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title":    currentTitle += string
        case "category": currentCategory += string
        case "pubDate":  currentPubDate += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "item" {
            insideItem = false
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            let date = formatter.date(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
            items.append(RSSItem(title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                  category: currentCategory.trimmingCharacters(in: .whitespacesAndNewlines),
                                  pubDate: date))
        }
    }
}
