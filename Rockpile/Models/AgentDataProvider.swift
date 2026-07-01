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

    /// 用户可见的状态描述
    @MainActor var displayName: String {
        switch self {
        case .disconnected:    return L10n.s("provider.disconnected")
        case .connecting:      return L10n.s("provider.connecting")
        case .connected:       return L10n.s("provider.connected")
        case .error(let msg):  return msg
        }
    }
}

/// 数据源类型
enum ProviderType: String, Sendable, CaseIterable {
    case socket      // Unix/TCP socket (SocketServer)
    case gateway     // Gateway WebSocket (GatewayClient)
    case statusPage  // 状态页轮询 (ServiceStatusMonitor)
    case custom      // 用户自定义连接
}

/// Agent 数据源协议 — 统一接口管理所有连接类型
///
/// v2.1: 增加生命周期回调 (lil-agents AgentSession 风格)
///
/// SocketServer、GatewayClient 等服务实现此协议，
/// ProviderRegistry 统一管理注册和状态查询。
@MainActor
protocol AgentDataProvider: AnyObject {
    var providerType: ProviderType { get }
    var providerName: String { get }
    var connectionState: ProviderConnectionState { get }
    var creatureType: CreatureType? { get }

    /// 连接状态变化回调 (lil-agents onProcessExit 模式)
    var onConnectionChange: ((ProviderConnectionState) -> Void)? { get set }

    func connectProvider()
    func disconnectProvider()
}

/// Default implementation for optional callbacks
extension AgentDataProvider {
    var onConnectionChange: ((ProviderConnectionState) -> Void)? {
        get { nil }
        set { /* opt-in by conforming types */ }
    }
}

/// Provider 工厂 — 类似 lil-agents 的 AgentProvider.createSession() 模式
///
/// 根据 ProviderType 创建对应的 provider 实例，简化初始化逻辑。
enum ProviderFactory {
    @MainActor
    static func provider(for type: ProviderType) -> (any AgentDataProvider)? {
        switch type {
        case .socket:     return SocketServer.shared
        case .gateway:    return GatewayClient.shared
        case .statusPage: return nil  // Managed by ServiceStatusMonitor
        case .custom:     return nil  // User-configured
        }
    }

    /// 创建并注册所有内置 provider
    @MainActor
    static func registerBuiltinProviders() {
        let registry = ProviderRegistry.shared
        if let socket = provider(for: .socket) {
            registry.register(socket)
        }
        if let gateway = provider(for: .gateway) {
            registry.register(gateway)
        }
    }
}
