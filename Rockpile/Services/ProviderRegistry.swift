import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "ProviderRegistry")

/// 数据源注册表 — 管理所有 AgentDataProvider 实例
///
/// 统一查询所有连接的状态、已连接数据源、按类型过滤等。
@MainActor
@Observable
final class ProviderRegistry {
    static let shared = ProviderRegistry()

    private(set) var providers: [any AgentDataProvider] = []

    private init() {}

    // MARK: - Registration

    func register(_ provider: any AgentDataProvider) {
        // Avoid duplicate registration
        guard !providers.contains(where: { $0.providerName == provider.providerName }) else { return }
        providers.append(provider)
        logger.info("Registered provider: \(provider.providerName) (\(provider.providerType.rawValue))")
    }

    func unregister(_ provider: any AgentDataProvider) {
        providers.removeAll { $0.providerName == provider.providerName }
    }

    // MARK: - Queries

    /// 所有已连接的数据源
    var connectedProviders: [any AgentDataProvider] {
        providers.filter { $0.connectionState.isConnected }
    }

    /// 所有数据源的连接状态
    var allConnectionStates: [(name: String, state: ProviderConnectionState)] {
        providers.map { ($0.providerName, $0.connectionState) }
    }

    /// 按类型过滤
    func providers(ofType type: ProviderType) -> [any AgentDataProvider] {
        providers.filter { $0.providerType == type }
    }

    /// 按生物类型过滤
    func providers(for creature: CreatureType) -> [any AgentDataProvider] {
        providers.filter { $0.creatureType == creature }
    }
}
