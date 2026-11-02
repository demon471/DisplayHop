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
            appState.move(.next)
        }
        KeyboardShortcuts.onKeyDown(for: .moveToPreviousDisplay) { [appState] in
            appState.move(.previous)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// App init 与 AppDelegate 共用的应用状态。
    /// App.init 先于 applicationDidFinishLaunching 执行，
    /// 因此用静态属性保证两处拿到同一个实例。
    static let sharedAppState = AppState()

    private var menuBarHost: MenuBarHost?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = MenuBarHost(appState: Self.sharedAppState)
        host.start()
        menuBarHost = host

        // 菜单栏图标被隐藏时，启动后给出可操作的恢复入口。
        // 此时用户既看不到菜单栏入口，也没有其他界面可以操作，
        // 因此用 NSAlert（不依赖 SwiftUI 环境，启动时必定可用）作为兼容性最好的兜底。
        guard !AppPreferences.shared.showMenuBarIcon else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("菜单栏图标已隐藏", comment: "隐藏图标后启动的弹窗标题")
            alert.informativeText = NSLocalizedString(
                "屏跃仍在后台运行，全局快捷键可正常使用。\n你可以重新显示菜单栏图标，或退出 App。",
                comment: "隐藏图标后启动的弹窗说明"
            )
            alert.addButton(withTitle: NSLocalizedString("显示菜单栏图标", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("退出", comment: ""))
            if alert.runModal() == .alertFirstButtonReturn {
                AppPreferences.shared.showMenuBarIcon = true
            } else {
                NSApp.terminate(nil)
            }
        }
    }
}
