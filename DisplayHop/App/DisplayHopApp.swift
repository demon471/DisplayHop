import Combine
import KeyboardShortcuts
import SwiftUI

// 快捷键定义。默认值参照 Wins 的风格（Control + Option + 方向键）。
// 注意：KeyboardShortcuts 2.x 的默认快捷键参数标签是 `default:`（3.x 改名为 `initial:`）。
extension KeyboardShortcuts.Name {
    static let moveToNextDisplay = Self(
        "moveToNextDisplay",
        default: .init(.rightArrow, modifiers: [.control, .option])
    )
    static let moveToPreviousDisplay = Self(
        "moveToPreviousDisplay",
        default: .init(.leftArrow, modifiers: [.control, .option])
    )
}

@main
struct DisplayHopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 菜单栏见 MenuBarHost（NSStatusItem），设置窗口见 SettingsWindowController（NSWindow）。
        // 这里留空 Settings 占位：SwiftUI App 至少需要一个 scene，实际界面全部手动管理。
        Settings { EmptyView() }
    }

    init() {
        // 首次使用且未授权时，由系统弹一次引导。
        AccessibilityPermission.openSystemPaneIfUngranted()

        let appState = AppDelegate.sharedAppState
        KeyboardShortcuts.onKeyDown(for: .moveToNextDisplay) { [appState] in
            Log.hotkey.notice("快捷键触发：移动到下一屏")
            appState.move(.next)
        }
        KeyboardShortcuts.onKeyDown(for: .moveToPreviousDisplay) { [appState] in
            Log.hotkey.notice("快捷键触发：移动到上一屏")
            appState.move(.previous)
        }

        Log.core.notice("启动完成，辅助功能授权：\(AccessibilityPermission.isGranted)")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// App init 与 AppDelegate 共用的应用状态。
    /// App.init 先于 applicationDidFinishLaunching 执行，
    /// 因此用静态属性保证两处拿到同一个实例。
    static let sharedAppState = AppState()

    private var menuBarHost: MenuBarHost?
    private var preferencesCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = MenuBarHost(appState: Self.sharedAppState)
        host.start()
        menuBarHost = host

        // 菜单栏图标 / 程序坞图标 两个开关相互独立。
        // 任意一个变化都要重新应用激活策略。
        preferencesCancellable = AppPreferences.shared.$showMenuBarIcon
            .combineLatest(AppPreferences.shared.$showDockIcon)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.updatePresenceMode()
            }
        updatePresenceMode()

        // 未授权时给出可操作的提示。
        // 系统自带的 AX 授权弹窗不一定会自动消失，且不提供跳转按钮，
        // 所以用自己的弹窗 + 直接打开系统设置面板。
        if !AccessibilityPermission.isGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("需要辅助功能权限", comment: "未授权提示标题")
                alert.informativeText = NSLocalizedString(
                    "辅助功能权限用于读取和移动其他应用的窗口。授权后快捷键才能生效。",
                    comment: "未授权提示说明"
                )
                alert.addButton(withTitle: NSLocalizedString("打开系统设置", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("稍后再说", comment: ""))
                if alert.runModal() == .alertFirstButtonReturn {
                    AccessibilityPermission.openSystemPane()
                }
            }
        }

        // 两个图标都关掉 → App 完全隐形，用户找不到任何入口。
        // 启动时弹一次提示，提供恢复按钮。
        if !AppPreferences.shared.hasVisibleEntryPoint {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("图标已全部隐藏", comment: "无入口提示标题")
                alert.informativeText = NSLocalizedString(
                    "菜单栏图标和程序坞图标都已隐藏，屏跃仍在后台运行，全局快捷键可正常使用。\n你可以重新显示其中任意一个图标，或退出 App。",
                    comment: "无入口提示说明"
                )
                alert.addButton(withTitle: NSLocalizedString("显示菜单栏图标", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("显示程序坞图标", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("退出", comment: ""))
                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    AppPreferences.shared.showMenuBarIcon = true
                case .alertSecondButtonReturn:
                    AppPreferences.shared.showDockIcon = true
                default:
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// 点击 Dock 图标时打开设置窗口（仅 Dock 模式下有 Dock 图标）。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    // MARK: - 呈现方式

    /// 两个图标相互独立：
    ///   菜单栏图标 → NSStatusItem.isVisible
    ///   程序坞图标 → 激活策略（.regular 有图标 / .accessory 无图标）
    ///
    /// 组合起来：
    ///   都显示   → 菜单栏图标 + Dock 图标
    ///   只菜单栏 → .accessory，纯菜单栏应用
    ///   只 Dock  → .regular，只有 Dock 图标
    ///   都隐藏   → .accessory 且无状态栏项，App 完全隐形
    private func updatePresenceMode() {
        let showDock = AppPreferences.shared.showDockIcon

        if showDock {
            NSApp.setActivationPolicy(.regular)
            NSApp.mainMenu = makeMainMenu()
        } else {
            NSApp.setActivationPolicy(.accessory)
            NSApp.mainMenu = nil
        }
    }

    /// Dock 模式下的主菜单（.regular 的应用需要主菜单，否则没有应用菜单）。
    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: NSLocalizedString("关于屏跃", comment: ""),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: NSLocalizedString("设置…", comment: ""),
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: NSLocalizedString("退出屏跃", comment: ""),
            action: #selector(NSApplication.terminate),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        return mainMenu
    }

    @objc private func openSettingsFromMenu() {
        SettingsWindowController.shared.show()
    }
}
