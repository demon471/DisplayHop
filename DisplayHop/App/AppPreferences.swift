import Foundation
import SwiftUI

/// 用户偏好。轻量场景，直接用 UserDefaults 持久化。
/// 使用单例是因为菜单栏场景（App）和设置窗口（View）需要共享同一份状态。
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private enum Key {
        static let showMenuBarIcon = "showMenuBarIcon"
    }

    /// 是否在菜单栏显示图标。
    /// 关闭后菜单栏图标消失；下次启动 App 时会自动弹出设置窗口，避免用户无从操作。
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 首次启动默认显示图标。
        if defaults.object(forKey: Key.showMenuBarIcon) == nil {
            showMenuBarIcon = true
        } else {
            showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        }
    }
}
