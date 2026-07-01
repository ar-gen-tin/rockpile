import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.rockpile.app", category: "ServiceStatusMonitor")

/// 服务状态监控 — 基于 UpTo 的轮询设计
///
/// 管理多个 StatusProvider，定时轮询所有服务状态。
/// UI 通过 `results` 获取最新状态，通过 `overallStatus` 获取总体健康度。
@MainActor
@Observable
final class ServiceStatusMonitor {
    static let shared = ServiceStatusMonitor()

    /// 各服务最新状态 [serviceId: result]
    private(set) var results: [String: ServiceStatusResult] = [:]

    /// 是否正在刷新
    private(set) var isRefreshing = false

    private var providers: [any StatusProvider] = []
    private var pollingTimer: Timer?

    /// 上一次各服务状态 — 用于变更检测
    private var previousStatuses: [String: HealthStatus] = [:]

    private init() {}

    // MARK: - Provider Registration

    func register(_ provider: any StatusProvider) {
        providers.append(provider)
    }

    // MARK: - Polling

    func startPolling() {
        guard !providers.isEmpty else { return }
        stopPolling()

        // Immediate first fetch
        Task { await refreshNow() }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: RC.ServiceStatus.pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshNow()
            }
        }
        logger.info("Service status polling started (\(self.providers.count) providers)")
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Refresh

    func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await withTaskGroup(of: ServiceStatusResult?.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return try await provider.fetchStatus()
                    } catch {
                        logger.warning("Failed to fetch \(provider.service.name): \(error.localizedDescription)")
                        return ServiceStatusResult(
                            service: provider.service,
                            status: .unknown,
                            components: [],
                            checkedAt: Date()
                        )
                    }
                }
            }

            for await result in group {
                guard let result else { continue }
                let serviceId = result.service.id

                // Detect status change for notification
                let previousStatus = previousStatuses[serviceId]
                if let previous = previousStatus, previous != result.status, result.status > previous {
                    NotificationManager.shared.notifyServiceStatusChange(
                        serviceName: result.service.name,
                        status: result.status.displayName
                    )
                }
                previousStatuses[serviceId] = result.status

                results[serviceId] = result
            }
        }
    }

    // MARK: - Computed

    /// 所有服务中最差的状态
    var overallStatus: HealthStatus {
        results.values.map(\.status).max() ?? .unknown
    }

    /// 按严重度排序的结果列表
    var sortedResults: [ServiceStatusResult] {
        results.values.sorted { $0.status > $1.status }
    }
}
