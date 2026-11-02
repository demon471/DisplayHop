import ServiceManagement

/// 登录时启动（macOS 13+ 的 SMAppService，无需 Helper）。
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LaunchAtLogin failed: \(error.localizedDescription)")
        }
    }
}
