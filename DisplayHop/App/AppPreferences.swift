import Foundation
import SwiftUI

/// 用户偏好。轻量场景，直接用 UserDefaults 持久化。
/// 使用单例是因为菜单栏场景（App）和设置窗口（View）需要共享同一份状态。
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private enum Key {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let showDockIcon = "showDockIcon"
    }

    /// 是否在菜单栏显示图标。
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }

    /// 是否在程序坞（Dock）显示图标。
    /// 与菜单栏图标相互独立：Dock 图标由激活策略决定
    /// （.regular 有图标 / .accessory 无图标）。
    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: Key.showDockIcon) }
    }

    /// 两个图标都关掉时，App 就没有任何可见入口了。
    var hasVisibleEntryPoint: Bool { showMenuBarIcon || showDockIcon }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 首次启动默认两个图标都显示。
        showMenuBarIcon = Self.bool(defaults, Key.showMenuBarIcon, default: true)
        showDockIcon = Self.bool(defaults, Key.showDockIcon, default: true)
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, default defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
