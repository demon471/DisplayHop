import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    let navigator: ScreenNavigator

    init(navigator: ScreenNavigator = ScreenNavigator()) {
        self.navigator = navigator
    }

    /// 执行移动。失败时用系统提示音反馈（保持菜单栏应用的克制交互）。
    func move(_ direction: MoveDirection) {
        let outcome = navigator.moveFocusedWindow(direction)
        switch outcome {
        case .moved:
            break
        case .noFocusedWindow, .singleDisplay, .failed:
            NSSound.beep()
        }
    }
}
