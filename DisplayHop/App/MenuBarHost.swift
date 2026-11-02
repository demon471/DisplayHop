import AppKit
import Combine

/// 菜单栏状态项的宿主。
///
/// 注意：不要用 SwiftUI 的 `MenuBarExtra(isInserted:)` 实现显隐——
/// 在 macOS 15 上它与 Settings 窗口组合会触发 SwiftUI 无限重绘
/// （requestUpdate → updateButton → setImage → _adjustLength 循环，主线程 100%）。
/// 这里用 NSStatusItem 手动管理，显隐等价于 `isVisible`，行为与 Rectangle 等工具一致。
@MainActor
final class MenuBarHost {
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "rectangle.on.rectangle.angled.fill",
                accessibilityDescription: NSLocalizedString("屏跃", comment: "")
            )
            // template = true 让系统按菜单栏前景色（深色菜单栏为纯白）渲染。
            image?.isTemplate = true
            button.image = image
        }
        item.menu = buildMenu()
        item.isVisible = AppPreferences.shared.showMenuBarIcon
        statusItem = item

        cancellable = AppPreferences.shared.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.statusItem?.isVisible = visible
            }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let next = NSMenuItem(
            title: NSLocalizedString("移动到下一屏", comment: ""),
            action: #selector(moveToNextDisplay),
            keyEquivalent: ""
        )
        next.target = self
        menu.addItem(next)

        let previous = NSMenuItem(
            title: NSLocalizedString("移动到上一屏", comment: ""),
            action: #selector(moveToPreviousDisplay),
            keyEquivalent: ""
        )
        previous.target = self
        menu.addItem(previous)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: NSLocalizedString("设置…", comment: ""),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let permission = NSMenuItem(
            title: NSLocalizedString("检查辅助功能权限…", comment: ""),
            action: #selector(checkPermission),
            keyEquivalent: ""
        )
        permission.target = self
        menu.addItem(permission)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: NSLocalizedString("退出屏跃", comment: ""),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Actions

    @objc private func moveToNextDisplay() { appState.move(.next) }
    @objc private func moveToPreviousDisplay() { appState.move(.previous) }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func checkPermission() { AccessibilityPermission.openSystemPane() }
    @objc private func quit() { NSApp.terminate(nil) }
}
