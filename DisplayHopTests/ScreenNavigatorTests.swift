import XCTest
@testable import DisplayHop

/// 记录所有 AX 写入调用的 Mock，同时模拟还原/移动对窗口状态的影响。
private final class MockWindowController: WindowControlling {
    var window: FocusedWindow?
    private(set) var minimizedCalls: [Bool] = []
    private(set) var fullScreenCalls: [Bool] = []
    private(set) var positionCalls: [WindowFrame] = []
    var positionSucceeds = true

    init(window: FocusedWindow?) {
        self.window = window
    }

    func focusedWindow() -> FocusedWindow? { window }

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
}

@MainActor
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
            title: "Test",
            backing: NSObject()
        )
    }

    // MARK: - 前置条件

    func testNoFocusedWindow() {
        let controller = MockWindowController(window: nil)
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])
        XCTAssertEqual(navigator.moveFocusedWindow(.next), .noFocusedWindow)
    }

    func testSingleDisplayShortCircuits() {
        let controller = MockWindowController(window: focusedWindow(x: 0, y: 0))
        let navigator = makeNavigator(controller: controller, displays: [Self.main])
        XCTAssertEqual(navigator.moveFocusedWindow(.next), .singleDisplay)
        XCTAssertTrue(controller.positionCalls.isEmpty)
    }

    // MARK: - 正向移动

    func testNextMovesToRightDisplayWithMappedPosition() {
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 200))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        XCTAssertEqual(navigator.moveFocusedWindow(.next), .moved(displayName: "External"))
        XCTAssertEqual(controller.positionCalls.count, 1)

        let position = try! XCTUnwrap(controller.positionCalls.first)
        XCTAssertEqual(position.minX, 2020) // 100 + 1920（同尺寸屏平移）
        XCTAssertEqual(position.minY, 200)
    }

    func testNextWrapsFromLastDisplayToFirst() {
        let controller = MockWindowController(window: focusedWindow(x: 2000, y: 0))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        XCTAssertEqual(navigator.moveFocusedWindow(.next), .moved(displayName: "Built-in"))
        let position = try! XCTUnwrap(controller.positionCalls.first)
        XCTAssertEqual(position.minX, 80) // 2000 - 1920
    }

    func testPreviousWrapsFromFirstDisplayToLast() {
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 0))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        XCTAssertEqual(navigator.moveFocusedWindow(.previous), .moved(displayName: "External"))
        let position = try! XCTUnwrap(controller.positionCalls.first)
        XCTAssertEqual(position.minX, 2020)
    }

    func testThreeDisplaysFollowScreenOrder() {
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

        XCTAssertEqual(navigator.moveFocusedWindow(.next), .moved(displayName: "Built-in"))
    }

    // MARK: - 边界情况

    func testMinimizedWindowIsRestoredBeforeMoving() {
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 0, minimized: true))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        XCTAssertEqual(navigator.moveFocusedWindow(.next), .moved(displayName: "External"))
        XCTAssertEqual(controller.minimizedCalls, [false])
        XCTAssertEqual(controller.positionCalls.count, 1)
    }

    func testFullScreenWindowExitsFullScreenBeforeMoving() {
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 0, fullScreen: true))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        XCTAssertEqual(navigator.moveFocusedWindow(.next), .moved(displayName: "External"))
        XCTAssertEqual(controller.fullScreenCalls, [false])
        XCTAssertEqual(controller.positionCalls.count, 1)
    }

    func testSetPositionFailureReportsFailed() {
        let controller = MockWindowController(window: focusedWindow(x: 100, y: 0))
        controller.positionSucceeds = false
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        XCTAssertEqual(navigator.moveFocusedWindow(.next), .failed)
    }

    func testOrphanWindowStillMovesToNearestDisplay() {
        // 窗口位置不属于任何屏幕（显示器断开遗留），也应能移到有效屏幕。
        let controller = MockWindowController(window: focusedWindow(x: 6000, y: 6000))
        let navigator = makeNavigator(controller: controller, displays: [Self.main, Self.external])

        let outcome = navigator.moveFocusedWindow(.next)
        XCTAssertEqual(outcome, .moved(displayName: "External"))
        let position = try! XCTUnwrap(controller.positionCalls.first)
        // 映射结果必须落在目标屏可见区域内。
        XCTAssertGreaterThanOrEqual(position.minX, Self.external.visibleFrame.minX)
        XCTAssertLessThanOrEqual(position.maxX, Self.external.visibleFrame.maxX)
    }
}
