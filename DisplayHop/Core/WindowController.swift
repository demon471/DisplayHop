import AppKit
import ApplicationServices

// MARK: - 窗口操作抽象
//
// ScreenNavigator 的移动逻辑只依赖 WindowControlling 协议，
// AX 实现需要辅助功能权限，单元测试中用 Mock 替换。
//
// 性能：AX 的每次属性读取都是一次跨进程 XPC 往返（约 0.1~1ms）。
// 所以这里尽量少读属性：标题等移动用不到的信息不取，
// 同一个窗口复用同一个 AXUIElement，避免重复查询聚焦窗口。

/// 当前聚焦窗口的快照。`backing` 持有 AX 元素本体，
/// 由 AX 实现用于后续写入操作。
struct FocusedWindow: Equatable {
    var frame: WindowFrame
    var isMinimized: Bool
    var isFullScreen: Bool
    var backing: AnyObject?

    static func == (lhs: FocusedWindow, rhs: FocusedWindow) -> Bool {
        lhs.frame == rhs.frame
            && lhs.isMinimized == rhs.isMinimized
            && lhs.isFullScreen == rhs.isFullScreen
    }
}

enum MoveDirection {
    case next
    case previous
}

enum MoveOutcome: Equatable {
    /// 已移动到指定显示器。
    case moved(displayName: String)
    /// 当前没有可操作的聚焦窗口。
    case noFocusedWindow
    /// 辅助功能权限未授予。
    case notAuthorized
    /// 只连接了一块显示器。
    case singleDisplay
    /// AX 写入失败（窗口不可移动等）。
    case failed
}

protocol WindowControlling {
    func focusedWindow() -> FocusedWindow?

    /// 只重新读取位置和尺寸（复用已有 AX 元素，2 次 XPC）。
    /// 退出全屏/还原之后窗口尺寸会变，需要重新读。
    func refreshFrame(_ window: FocusedWindow) -> WindowFrame?

    @discardableResult
    func setMinimized(_ window: FocusedWindow, to minimized: Bool) -> Bool
    @discardableResult
    func setFullScreen(_ window: FocusedWindow, to fullScreen: Bool) -> Bool
    @discardableResult
    func setPosition(_ window: FocusedWindow, to frame: WindowFrame) -> Bool

    /// 等待窗口退出全屏。AX 写入是异步生效的，
    /// 不等的话读到的还是全屏尺寸，移动位置会算错。
    func waitForFullScreenExit(_ window: FocusedWindow) async

    /// 同时设置位置和尺寸（铺满整屏的窗口跨屏时需要）。
    @discardableResult
    func setFrame(_ window: FocusedWindow, to frame: WindowFrame) -> Bool
}

extension WindowControlling {
    func refreshFrame(_ window: FocusedWindow) -> WindowFrame? { nil }
    func waitForFullScreenExit(_ window: FocusedWindow) async {}
    @discardableResult
    func setFrame(_ window: FocusedWindow, to frame: WindowFrame) -> Bool {
        setPosition(window, to: frame)
    }
}

// MARK: - AX 实现

/// 基于辅助功能 API 的窗口操作实现。
/// 需要用户在系统设置中授予辅助功能权限。
final class AXWindowController: WindowControlling {
    private let systemWideElement = AXUIElementCreateSystemWide()

    /// AX 属性名：窗口是否全屏（公开头文件未导出常量，值为固定字符串）。
    private static let fullScreenAttribute = "AXFullScreen"

    func focusedWindow() -> FocusedWindow? {
        guard let app = copyValue(systemWideElement, kAXFocusedApplicationAttribute),
              let windowValue = copyValue(app as! AXUIElement, kAXFocusedWindowAttribute)
        else { return nil }

        let element = windowValue as! AXUIElement
        guard let frame = Self.frame(of: element) else { return nil }

        return FocusedWindow(
            frame: frame,
            isMinimized: Self.boolValue(element, kAXMinimizedAttribute) ?? false,
            isFullScreen: Self.boolValue(element, Self.fullScreenAttribute) ?? false,
            backing: element
        )
    }

    func refreshFrame(_ window: FocusedWindow) -> WindowFrame? {
        guard let backing = window.backing else { return nil }
        return Self.frame(of: backing as! AXUIElement)
    }

    func setMinimized(_ window: FocusedWindow, to minimized: Bool) -> Bool {
        setValue(window, attribute: kAXMinimizedAttribute, to: minimized)
    }

    func setFullScreen(_ window: FocusedWindow, to fullScreen: Bool) -> Bool {
        setValue(window, attribute: Self.fullScreenAttribute, to: fullScreen)
    }

    func setPosition(_ window: FocusedWindow, to frame: WindowFrame) -> Bool {
        guard let backing = window.backing else { return false }
        let element = backing as! AXUIElement
        var point = CGPoint(x: frame.minX, y: frame.minY)
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    func setFrame(_ window: FocusedWindow, to frame: WindowFrame) -> Bool {
        guard let backing = window.backing else { return false }
        let element = backing as! AXUIElement

        // AX 写入是异步的：连续写入会互相覆盖。
        // 实测（外屏 2048宽 → 内屏 1728宽）：
        //   先缩小宽度 → 等 100ms → 移动位置 → 等 100ms → 写完整尺寸
        // 不加延时的话，缩小还没生效就移动位置，窗口跨在两屏之间，
        // 后续尺寸写入被忽略（宽度停在旧值）。
        writeSize(element, frame.width, frame.height)
        Thread.sleep(forTimeInterval: 0.1)
        writePosition(element, frame.minX, frame.minY)
        Thread.sleep(forTimeInterval: 0.1)
        writeSize(element, frame.width, frame.height)
        Thread.sleep(forTimeInterval: 0.1)
        writePosition(element, frame.minX, frame.minY)
        return true
    }

    private func writePosition(_ element: AXUIElement, _ x: Double, _ y: Double) {
        var point = CGPoint(x: x, y: y)
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private func writeSize(_ element: AXUIElement, _ width: Double, _ height: Double) {
        var size = CGSize(width: width, height: height)
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    func waitForFullScreenExit(_ window: FocusedWindow) async {
        guard let backing = window.backing else { return }
        let element = backing as! AXUIElement
        // AXFullScreen 变成 false 需要一点时间（系统动画 + 异步通知）。
        // 最多等 600ms，超时就用现有 frame 继续，保证不会卡住。
        for _ in 0..<30 {
            if (Self.boolValue(element, Self.fullScreenAttribute) ?? false) == false {
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: Private

    private static func frame(of element: AXUIElement) -> WindowFrame? {
        guard let position = pointValue(element, kAXPositionAttribute),
              let size = sizeValue(element, kAXSizeAttribute)
        else { return nil }
        return WindowFrame(
            minX: position.x,
            minY: position.y,
            width: size.width,
            height: size.height
        )
    }

    private func setValue(_ window: FocusedWindow, attribute: String, to value: Bool) -> Bool {
        guard let backing = window.backing else { return false }
        let element = backing as! AXUIElement
        return AXUIElementSetAttributeValue(
            element, attribute as CFString, value as CFBoolean
        ) == .success
    }

    private func copyValue(_ element: CFTypeRef, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element as! AXUIElement, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    private static func pointValue(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = typedAXValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeValue(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = typedAXValue(element, attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private static func typedAXValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }

    private static func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value, let bool = value as? Bool else { return nil }
        return bool
    }
}

// MARK: - 辅助功能权限

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// 直接打开系统设置的辅助功能面板。
    /// 不用 AXIsProcessTrustedWithOptions 的弹窗：那个弹窗授权后不会自动消失，
    /// 且重复调用会叠加，体验差。
    static func openSystemPane() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }

    /// 首次使用引导：未授权时弹一次系统提示（系统仅弹一次），已授权时什么都不做。
    static func openSystemPaneIfUngranted() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
