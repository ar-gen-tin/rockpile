import Foundation

/// 数据源连接状态 — 基于 UpTo 的 Provider 抽象
enum ProviderConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// 数据源类型
enum ProviderType: String, Sendable {
    case socket      // Unix/TCP socket (SocketServer)
    case gateway     // Gateway WebSocket (GatewayClient)
    case statusPage  // 状态页轮询 (ServiceStatusMonitor)
    case custom      // 用户自定义连接
}

/// Agent 数据源协议 — 统一接口管理所有连接类型
///
/// SocketServer、GatewayClient 等服务实现此协议，
/// ProviderRegistry 统一管理注册和状态查询。
@MainActor
protocol AgentDataProvider: AnyObject {
    var providerType: ProviderType { get }
    var providerName: String { get }
    var connectionState: ProviderConnectionState { get }
    var creatureType: CreatureType? { get }
    func connectProvider()
    func disconnectProvider()
}
