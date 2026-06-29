import Foundation
import ServiceManagement

/// 开机自启管理（macOS 13+，基于 ServiceManagement 的 SMAppService）。
enum LaunchAtLoginManager {

    /// 应用开机自启开关。
    static func apply(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            CWLog.error("开机自启设置失败: \(error.localizedDescription)")
        }
    }

    /// 当前是否已启用开机自启。
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
