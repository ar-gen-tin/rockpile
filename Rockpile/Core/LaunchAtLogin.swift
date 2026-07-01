import ServiceManagement

/// 开机启动管理 — 基于 SMAppService (macOS 13+)
enum LaunchAtLogin {

    /// 当前开机启动是否开启
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Silently fail — user may need to grant permission in System Settings
            }
        }
    }
}
