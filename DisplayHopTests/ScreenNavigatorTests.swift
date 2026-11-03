import XCTest
@testable import DisplayHop

/// 记录所有 AX 写入调用的 Mock，同时模拟还原/移动对窗口状态的影响。
private final class MockWindowController: WindowControlling {
    var window: FocusedWindow?
    private(set) var minimizedCalls: [Bool] = []
    private(set) var fullScreenCalls: [Bool] = []
    private(set) var positionCalls: [WindowFrame] = []
    private(set) var frameCalls: [WindowFrame] = []
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

    func setFrame(_ window: FocusedWindow, to frame: WindowFrame) -> Bool {
        frameCalls.append(frame)
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
// MARK: - 平铺满屏窗口

    /// 「填充」状态：窗口比可见区四周内缩 8pt（macOS 的窗口边距）。
    /// 实测数据：可见区 1728x1079 @(0,38) → 窗口 1712x1063 @(8,46)
    func testFilledWindowStaysFilledOnTargetDisplay() async {
        let controller = MockWindowController(
            window: FocusedWindow(
                frame: WindowFrame(minX: 8, minY: 46, width: 1712, height: 1063),
                isMinimized: false,
                isFullScreen: false,
                backing: NSObject()
            )
        )
        let main = DisplayInfo(
            frame: DisplayFrame(minX: 0, minY: 0, width: 1728, height: 1117),
            visibleFrame: DisplayFrame(minX: 0, minY: 38, width: 1728, height: 1079),
            name: "Built-in"
        )
        let external = DisplayInfo(
            frame: DisplayFrame(minX: 1728, minY: 0, width: 2048, height: 1152),
            visibleFrame: DisplayFrame(minX: 1728, minY: 0, width: 2048, height: 1152),
            name: "B2724A"
        )
        let navigator = ScreenNavigator(controller: controller, displaysProvider: { [main, external] })

        let outcome = await navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .moved(displayName: "B2724A"))

        // 必须走 setFrame（位置+尺寸一起改），不能只改位置
        XCTAssertEqual(controller.frameCalls.count, 1)
        XCTAssertTrue(controller.positionCalls.isEmpty)

        // 零边距：位置取屏幕原点，尺寸取整屏
        let frame = try! XCTUnwrap(controller.frameCalls.first)
        XCTAssertEqual(frame.minX, 1728)
        XCTAssertEqual(frame.minY, 0)
        XCTAssertEqual(frame.width, 2048)
        XCTAssertEqual(frame.height, 1152)
    }

    /// 「缩放」状态：与可见区完全相等（内缩 0）。
    func testZoomedWindowWithoutMarginFillsTargetExactly() async {
        let controller = MockWindowController(
            window: FocusedWindow(
                frame: WindowFrame(minX: 0, minY: 38, width: 1728, height: 1079),
                isMinimized: false,
                isFullScreen: false,
                backing: NSObject()
            )
        )
        let main = DisplayInfo(
            frame: DisplayFrame(minX: 0, minY: 0, width: 1728, height: 1117),
            visibleFrame: DisplayFrame(minX: 0, minY: 38, width: 1728, height: 1079),
            name: "Built-in"
        )
        let external = DisplayInfo(
            frame: DisplayFrame(minX: 1728, minY: 0, width: 2048, height: 1152),
            visibleFrame: DisplayFrame(minX: 1728, minY: 0, width: 2048, height: 1152),
            name: "B2724A"
        )
        let navigator = ScreenNavigator(controller: controller, displaysProvider: { [main, external] })

        _ = await navigator.moveFocusedWindow(.next)
        let frame = try! XCTUnwrap(controller.frameCalls.first)
        XCTAssertEqual(frame.minX, 1728)
        XCTAssertEqual(frame.minY, 0)
        XCTAssertEqual(frame.width, 2048)
        XCTAssertEqual(frame.height, 1152)
    }

    /// 比可见区小很多（超过容忍度）的窗口不应被当成「铺满」，
    /// 移动时只改位置、保持原尺寸。
    func testNearlyFullButNotFilledWindowKeepsItsSize() async {
        let controller = MockWindowController(
            window: FocusedWindow(
                frame: WindowFrame(minX: 100, minY: 100, width: 1200, height: 800),
                isMinimized: false,
                isFullScreen: false,
                backing: NSObject()
            )
        )
        let main = DisplayInfo(
            frame: DisplayFrame(minX: 0, minY: 0, width: 1728, height: 1117),
            visibleFrame: DisplayFrame(minX: 0, minY: 38, width: 1728, height: 1079),
            name: "Built-in"
        )
        let external = DisplayInfo(
            frame: DisplayFrame(minX: 1728, minY: 0, width: 2048, height: 1152),
            visibleFrame: DisplayFrame(minX: 1728, minY: 0, width: 2048, height: 1152),
            name: "B2724A"
        )
        let navigator = ScreenNavigator(controller: controller, displaysProvider: { [main, external] })

        _ = await navigator.moveFocusedWindow(.next)
        XCTAssertTrue(controller.frameCalls.isEmpty)
        XCTAssertEqual(controller.positionCalls.count, 1)
    }

    /// 普通窗口（尺寸不等于可见区）不应被放大。
    func testNonZoomedWindowUsesPositionOnly() async {
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 200))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        _ = await navigator.moveFocusedWindow(.next)
        XCTAssertTrue(controller.frameCalls.isEmpty)
        XCTAssertEqual(controller.positionCalls.count, 1)
    }

    /// 比目标屏还大的窗口，移过去后要缩小，否则会超出屏幕。
    func testWindowTooLargeForTargetIsShrunkToFit() async {
        let big = DisplayInfo(
            frame: DisplayFrame(minX: 0, minY: 0, width: 2560, height: 1440),
            visibleFrame: DisplayFrame(minX: 0, minY: 0, width: 2560, height: 1400),
            name: "Big"
        )
        let small = DisplayInfo(
            frame: DisplayFrame(minX: 2560, minY: 0, width: 1280, height: 800),
            visibleFrame: DisplayFrame(minX: 2560, minY: 0, width: 1280, height: 800),
            name: "Small"
        )
        let controller = MockWindowController(
            window: FocusedWindow(
                frame: WindowFrame(minX: 100, minY: 100, width: 2000, height: 1200),
                isMinimized: false,
                isFullScreen: false,
                backing: NSObject()
            )
        )
        let navigator = ScreenNavigator(controller: controller, displaysProvider: { [big, small] })

        _ = await navigator.moveFocusedWindow(.next)
        let frame = try! XCTUnwrap(controller.positionCalls.first)
        XCTAssertEqual(frame.width, 1280)
        XCTAssertEqual(frame.height, 800)
    }
}

// MARK: - 系统填充
}
