import XCTest
@testable import DisplayHop

/// 记录所有 AX 写入调用的 Mock，同时模拟还原/移动对窗口状态的影响。
private final class MockWindowController: WindowControlling {
    var window: FocusedWindow?
    private(set) var minimizedCalls: [Bool] = []
    private(set) var fullScreenCalls: [Bool] = []
    private(set) var positionCalls: [WindowFrame] = []
    private(set) var refreshCount = 0
    private(set) var waitForFullScreenExitCount = 0
    var positionSucceeds = true
    /// 模拟「退出全屏后窗口还原到某个尺寸」。
    var restoredFrame: WindowFrame?

    init(window: FocusedWindow?) {
        self.window = window
    }

    func focusedWindow() -> FocusedWindow? { window }

    func refreshFrame(_ window: FocusedWindow) -> WindowFrame? {
        refreshCount += 1
        return restoredFrame ?? self.window?.frame
    }

    func setMinimized(_ window: FocusedWindow, to minimized: Bool) -> Bool {
        minimizedCalls.append(minimized)
        self.window?.isMinimized = minimized
        return true
    }

    func setFullScreen(_ window: FocusedWindow, to fullScreen: Bool) -> Bool {
        fullScreenCalls.append(fullScreen)
        self.window?.isFullScreen = fullScreen
        return true
    }

    func setPosition(_ window: FocusedWindow, to frame: WindowFrame) -> Bool {
        guard positionSucceeds else { return false }
        positionCalls.append(frame)
        self.window?.frame = frame
        return true
    }

    func waitForFullScreenExit(_ window: FocusedWindow) async {
        waitForFullScreenExitCount += 1
    }
}

final class ScreenNavigatorTests: XCTestCase {

    private static let main = DisplayInfo(
        frame: DisplayFrame(minX: 0, minY: 0, width: 1920, height: 1080),
        visibleFrame: DisplayFrame(minX: 0, minY: 0, width: 1920, height: 1080),
        name: "Built-in"
    )

    private static let external = DisplayInfo(
        frame: DisplayFrame(minX: 1920, minY: 0, width: 1920, height: 1080),
        visibleFrame: DisplayFrame(minX: 1920, minY: 0, width: 1920, height: 1080),
        name: "External"
    )

    private func makeNavigator(
        controller: MockWindowController,
        displays: [DisplayInfo]
    ) -> ScreenNavigator {
        ScreenNavigator(controller: controller, displaysProvider: { displays })
    }

    private func focusedWindow(
        x: Double, y: Double,
        minimized: Bool = false,
        fullScreen: Bool = false
    ) -> FocusedWindow {
        FocusedWindow(
            frame: WindowFrame(minX: x, minY: y, width: 800, height: 600),
            isMinimized: minimized,
            isFullScreen: fullScreen,
            backing: NSObject()
        )
    }

    // MARK: - 前置条件

    func testNoFocusedWindow() async {
        let controller = MockWindowController(window: nil)
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])
        let outcome = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .noFocusedWindow)
    }

    func testSingleDisplayShortCircuits() async {
        let controller = MockWindowController(window: focusedWindow(x: 0, y: 0))
        let navigator = makeNavigator(controller: controller, displays: [Self.main])
        let outcome = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .singleDisplay)
        XCTAssertTrue(controller.positionCalls.isEmpty)
    }

    // MARK: - 正向移动

    func testNextMovesToRightDisplayWithMappedPosition() async {
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 200))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        let outcome = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .moved(displayName: "External"))
        XCTAssertEqual(controller.positionCalls.count, 1)

        let position = try! XCTUnwrap(controller.positionCalls.first)
        XCTAssertEqual(position.minX, 2020) // 100 + 1920（同尺寸屏平移）
        XCTAssertEqual(position.minY, 200)
    }

    func testNextWrapsFromLastDisplayToFirst() async {
        let controller = MockWindowController(window: focusedWindow(x: 2000, y: 0))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        let outcome = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .moved(displayName: "Built-in"))
        let position = try! XCTUnwrap(controller.positionCalls.first)
        XCTAssertEqual(position.minX, 80) // 2000 - 1920
    }

    func testPreviousWrapsFromFirstDisplayToLast() async {
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 0))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        let outcome = await navigator.moveFocusedWindow(.previous)
        XCTAssertEqual(outcome, .moved(displayName: "External"))
        let position = try! XCTUnwrap(controller.positionCalls.first)
        XCTAssertEqual(position.minX, 2020)
    }

    func testThreeDisplaysFollowScreenOrder() async {
        let left = Self.main
        let middle = Self.external
        let right = DisplayInfo(
            frame: DisplayFrame(minX: 3840, minY: 0, width: 1920, height: 1080),
            visibleFrame: DisplayFrame(minX: 3840, minY: 0, width: 1920, height: 1080),
            name: "Right"
        )
        // 传入乱序列表，验证内部排序后再导航：
        // 窗口在最右屏，next 回绕到最左的 Built-in。
        let controller = MockWindowController(window: focusedWindow(x: 3900, y: 0))
        let navigator = makeNavigator(controller: controller, displays: [right, left, middle])

        let outcome = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .moved(displayName: "Built-in"))
    }

    // MARK: - 边界情况

    func testMinimizedWindowIsRestoredBeforeMoving() async {
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 0, minimized: true))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        let outcome = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .moved(displayName: "External"))
        XCTAssertEqual(controller.minimizedCalls, [false])
        XCTAssertEqual(controller.positionCalls.count, 1)
    }

    func testSetPositionFailureReportsFailed() async {
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 0))
        controller.positionSucceeds = false
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        let outcome = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .failed)
    }

    func testOrphanWindowStillMovesToNearestDisplay() async {
        // 窗口位置不属于任何屏幕（显示器断开遗留），也应能移到有效屏幕。
        let controller = MockWindowController(window: focusedWindow(x: 6000, y: 6000))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        let outcome = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .moved(displayName: "External"))
        let position = try! XCTUnwrap(controller.positionCalls.first)
        // 映射结果必须落在目标屏可见区域内。
        XCTAssertGreaterThanOrEqual(position.minX, Self.external.visibleFrame.minX)
        XCTAssertLessThanOrEqual(position.maxX, Self.external.visibleFrame.maxX)
    }

    // MARK: - 全屏窗口

    func testFullScreenWindowRestoresFullScreenAfterMoving() async {
        // 回归用例：全屏窗口从内屏移到外屏后，应当仍是全屏。
        let controller = MockWindowController(window: focusedWindow(x: 0, y: 0, fullScreen: true))
        // 退出全屏后窗口还原成一个小窗口
        controller.restoredFrame = WindowFrame(minX: 100, minY: 100, width: 800, height: 600)
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        let outcome = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .moved(displayName: "External"))

        // 先退出全屏、移动、再恢复全屏
        XCTAssertEqual(controller.fullScreenCalls, [false, true])
        // 移动时用的是还原后的窗口尺寸，不是全屏尺寸
        let position = try! XCTUnwrap(controller.positionCalls.first)
        XCTAssertEqual(position.minX, 2020)
        XCTAssertEqual(position.width, 800)
        // 退出全屏后必须等状态生效，否则读到的还是全屏尺寸
        XCTAssertEqual(controller.waitForFullScreenExitCount, 1)
    }

    func testNonFullScreenWindowDoesNotTouchFullScreenState() async {
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 0))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        _ = await navigator.moveFocusedWindow(.next)
        XCTAssertTrue(controller.fullScreenCalls.isEmpty)
        XCTAssertEqual(controller.waitForFullScreenExitCount, 0)
    }

    func testFullScreenWindowThatCannotExitFullScreenStillMoves() async {
        // 某些 App 不支持退出全屏，这时仍要尽量移动，不能卡死。
        let controller = MockWindowController(window: focusedWindow(x: 0, y: 0, fullScreen: true))
        controller.restoredFrame = WindowFrame(minX: 0, minY: 0, width: 1920, height: 1080)
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        let outcome = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .moved(displayName: "External"))
        XCTAssertEqual(controller.positionCalls.count, 1)
    }

    // MARK: - 性能

    func testFrameIsRefreshedWithoutReQueryingFocusedWindow() async {
        // 优化点：退出全屏后只重读 position/size（refreshFrame），
        // 不重新调用 focusedWindow()（那会多花 5 次跨进程调用）。
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 0))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        _ = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(controller.refreshCount, 1)
    }
}
