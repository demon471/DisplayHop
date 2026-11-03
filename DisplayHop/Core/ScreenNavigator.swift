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

    func moveFocusedWindow(_ direction: MoveDirection) async -> MoveOutcome {
        // 注意：不在这里检查辅助功能权限。
        // 本类保持为不依赖系统权限的纯逻辑，便于单元测试；
        // 权限检查在 AppState 层做。
        guard let window = controller.focusedWindow() else {
            Log.ax.error("没有聚焦窗口")
            return .noFocusedWindow
        }

        let displays = DisplayGeometry.ordered(displaysProvider())
        guard displays.count > 1 else {
            Log.core.error("只有一块屏幕")
            return .singleDisplay
        }

        let currentIndex = DisplayGeometry.current(for: window.frame, in: displays)
            .flatMap { displays.firstIndex(of: $0) } ?? 0
        let targetIndex: Int = switch direction {
        case .next: (currentIndex + 1) % displays.count
        case .previous: (currentIndex - 1 + displays.count) % displays.count
        }
        let target = displays[targetIndex]

        // 记住原始状态：移动完成后要恢复。
        let wasFullScreen = window.isFullScreen
        let wasMinimized = window.isMinimized

        // 「铺满整屏」的窗口：不能只改位置，否则尺寸还是源屏的，到目标屏就不再铺满。
        let sourceDisplay = displays[currentIndex]
        let wasFilled = !wasFullScreen
            && DisplayGeometry.isFilled(window.frame, in: sourceDisplay)

        if wasMinimized {
            controller.setMinimized(window, to: false)
        }

        if wasFullScreen {
            // 全屏窗口必须先退出全屏才能移动位置。
            // 退出后要等状态真正生效，否则读到的还是全屏尺寸，映射会算错。
            controller.setFullScreen(window, to: false)
            await controller.waitForFullScreenExit(window)
        }

        // 退出全屏/还原后 frame 会变，只重新读位置和尺寸（2 次 XPC），
        // 不重新查询聚焦窗口（那要 7 次 XPC）。
        let currentFrame = controller.refreshFrame(window) ?? window.frame
        let source = DisplayGeometry.current(for: currentFrame, in: displays) ?? target

        if wasFilled {
            // 零边距铺满目标屏：位置到屏幕原点 + 尺寸取整屏，
            // 高度由系统自动钳制到该屏允许的最大值。
            let filled = DisplayGeometry.fillFrame(in: target)
            guard controller.setFrame(window, to: filled) else {
                Log.ax.error("写入窗口尺寸失败")
                return .failed
            }
            Log.core.notice(
                "已零边距铺满并移动到 \(target.name, privacy: .public)"
            )
            return .moved(displayName: target.name)
        }

        let mapped = DisplayGeometry.mappedFrame(of: currentFrame, from: source, to: target)
        // 目标屏比源屏小时，窗口可能装不下——缩小到能放下，避免超出屏幕边界。
        let fitted = DisplayGeometry.fittingSize(mapped, in: target)

        guard controller.setPosition(window, to: fitted) else {
            Log.ax.error("写入窗口位置失败")
            return .failed
        }

        // 恢复全屏：此时窗口已在目标屏上，会在目标屏进入全屏。
        // 这正是用户期望的行为——内屏全屏的窗口移到外屏后仍是全屏。
        if wasFullScreen {
            controller.setFullScreen(window, to: true)
        }

        Log.core.notice(
            "已移动到 \(target.name, privacy: .public)，新位置 x=\(mapped.minX) y=\(mapped.minY) 全屏=\(wasFullScreen)"
        )
        return .moved(displayName: target.name)
    }
}
