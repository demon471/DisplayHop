import AppKit
import Foundation

/// 跨屏移动的编排逻辑：
/// 找到聚焦窗口 → 确定当前屏幕 → 计算目标位置 → AX 写入。
/// 屏幕列表通过 `displaysProvider` 注入，可脱离真实显示器做单元测试。
final class ScreenNavigator {
    private let controller: WindowControlling
    private let displaysProvider: () -> [DisplayInfo]

    init(
        controller: WindowControlling = AXWindowController(),
        displaysProvider: @escaping () -> [DisplayInfo] = {
            NSScreen.screens.map { DisplayInfo(screen: $0) }
        }
    ) {
        self.controller = controller
        self.displaysProvider = displaysProvider
    }

    func moveFocusedWindow(_ direction: MoveDirection) -> MoveOutcome {
        guard let window = controller.focusedWindow() else { return .noFocusedWindow }

        let displays = DisplayGeometry.ordered(displaysProvider())
        guard displays.count > 1 else { return .singleDisplay }

        let currentIndex = DisplayGeometry.current(for: window.frame, in: displays)
            .flatMap { displays.firstIndex(of: $0) } ?? 0
        let targetIndex: Int = switch direction {
        case .next: (currentIndex + 1) % displays.count
        case .previous: (currentIndex - 1 + displays.count) % displays.count
        }
        let target = displays[targetIndex]

        if window.isMinimized {
            controller.setMinimized(window, to: false)
        }
        if window.isFullScreen {
            controller.setFullScreen(window, to: false)
        }

        // 退出全屏/最小化后 frame 可能变化，重新读取一次再做映射。
        let currentFrame = controller.focusedWindow()?.frame ?? window.frame
        let source = DisplayGeometry.current(for: currentFrame, in: displays) ?? target
        let mapped = DisplayGeometry.mappedFrame(of: currentFrame, from: source, to: target)

        guard controller.setPosition(window, to: mapped) else { return .failed }
        return .moved(displayName: target.name)
    }
}
