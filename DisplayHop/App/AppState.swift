import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    let navigator: ScreenNavigator

    /// 上一次移动的结果，用于设置页展示与排查。
    @Published private(set) var lastOutcome: MoveOutcome?

    init(navigator: ScreenNavigator = ScreenNavigator()) {
        self.navigator = navigator
    }

    /// 执行移动。失败时用系统提示音反馈（保持菜单栏应用的克制交互）。
    func move(_ direction: MoveDirection) {
        // 权限检查放在 App 层，ScreenNavigator 保持为不依赖系统权限的纯逻辑。
        guard AccessibilityPermission.isGranted else {
            Log.ax.error("辅助功能未授权，无法读取窗口")
            lastOutcome = .notAuthorized
            NSSound.beep()
            return
        }

        let outcome = navigator.moveFocusedWindow(direction)
        lastOutcome = outcome
        switch outcome {
        case .moved:
            break
        case .noFocusedWindow, .notAuthorized, .singleDisplay, .failed:
            NSSound.beep()
        }
    }
}
