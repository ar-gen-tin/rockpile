import Foundation

/// 自定义连接类型 — 自动检测或手动指定
enum ConnectionType: String, Codable, Sendable {
    case webSocket
    case tcp
    case http
    case unknown
}

/// 用户自定义连接 — 持久化到 UserDefaults
struct CustomConnection: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var url: String
    var type: ConnectionType
    var isEnabled: Bool

    init(name: String, url: String, type: ConnectionType = .unknown, isEnabled: Bool = true) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.type = type
        self.isEnabled = isEnabled
    }

    // MARK: - Persistence

    static func loadAll() -> [CustomConnection] {
        guard let data = AppSettings.customConnectionsData else { return [] }
        return (try? JSONDecoder().decode([CustomConnection].self, from: data)) ?? []
    }

    static func saveAll(_ connections: [CustomConnection]) {
        AppSettings.customConnectionsData = try? JSONEncoder().encode(connections)
    }
}
