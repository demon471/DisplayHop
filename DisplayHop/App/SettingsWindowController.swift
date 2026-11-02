import AppKit
import SwiftUI

/// 设置窗口控制器：NSWindow + NSHostingView 手动托管 SwiftUI 视图。
///
/// 不用 SwiftUI 的 Settings scene 是因为它的呈现依赖 SwiftUI 内部 action
/// （`showSettingsWindow:`），在没有 SwiftUI 菜单栏/responder 链的
/// 纯 NSStatusItem 环境下 sendAction 找不到处理器，窗口打不开。
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        if window == nil {
            let content = NSHostingView(rootView: SettingsView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = NSLocalizedString("设置", comment: "设置窗口标题")
            window.contentView = content
            window.isReleasedWhenClosed = false
            // 记住上次位置和大小；首次打开才居中，否则会盖掉自动恢复的位置。
            window.setFrameAutosaveName("SettingsWindow")
            if UserDefaults.standard.string(forKey: "NSWindow Frame SettingsWindow") == nil {
                window.center()
            }
            self.window = window
        }

        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
