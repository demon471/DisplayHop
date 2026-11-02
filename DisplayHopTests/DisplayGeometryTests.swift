import XCTest
@testable import DisplayHop

/// 跨屏几何计算：屏幕排序、归属判定、坐标映射与夹紧。
final class DisplayGeometryTests: XCTestCase {

    // MARK: - 测试用例构造器

    /// 1920×1080 主屏，可见区域同 frame（测试中未启用 Dock/菜单栏偏移）。
    private static let main = DisplayInfo(
        frame: DisplayFrame(minX: 0, minY: 0, width: 1920, height: 1080),
        visibleFrame: DisplayFrame(minX: 0, minY: 0, width: 1920, height: 1080),
        name: "Built-in"
    )

    /// 右侧同尺寸外接屏。
    private static let external = DisplayInfo(
        frame: DisplayFrame(minX: 1920, minY: 0, width: 1920, height: 1080),
        visibleFrame: DisplayFrame(minX: 1920, minY: 0, width: 1920, height: 1080),
        name: "External"
    )

    private func window(_ x: Double, _ y: Double, _ w: Double = 800, _ h: Double = 600) -> WindowFrame {
        WindowFrame(minX: x, minY: y, width: w, height: h)
    }

    // MARK: - ordered

    func testOrderedSortsLeftToRight() {
        let ordered = DisplayGeometry.ordered([Self.external, Self.main])
        XCTAssertEqual(ordered.map(\.name), ["Built-in", "External"])
    }

    func testOrderedStableForVerticalStack() {
        // 纵向排列（x 相同）时按 y 排序：上面的在前。
        let top = DisplayInfo(
            frame: DisplayFrame(minX: 0, minY: 0, width: 1920, height: 1080),
            visibleFrame: DisplayFrame(minX: 0, minY: 0, width: 1920, height: 1080),
            name: "Top"
        )
        let bottom = DisplayInfo(
            frame: DisplayFrame(minX: 0, minY: 1080, width: 1920, height: 1080),
            visibleFrame: DisplayFrame(minX: 0, minY: 1080, width: 1920, height: 1080),
            name: "Bottom"
        )
        XCTAssertEqual(DisplayGeometry.ordered([bottom, top]).map(\.name), ["Top", "Bottom"])
    }

    // MARK: - current

    func testCurrentPicksDisplayContainingWindow() {
        let current = DisplayGeometry.current(for: window(2500, 100), in: [Self.main, Self.external])
        XCTAssertEqual(current?.name, "External")
    }

    func testCurrentPicksLargerOverlapWhenWindowSpansTwoDisplays() {
        // 窗口横跨两屏，右边占更多面积 → 归属外接屏。
        let current = DisplayGeometry.current(for: window(1800, 100), in: [Self.main, Self.external])
        XCTAssertEqual(current?.name, "External")
    }

    func testCurrentReturnsNilForEmptyDisplays() {
        XCTAssertNil(DisplayGeometry.current(for: window(0, 0), in: []))
    }

    func testCurrentFallsBackToLargestOverlapForOrphanWindow() {
        // 窗口完全不在任何屏幕上（例如断开显示器后遗留），
        // 应该返回距离最近（重叠坐标上最大）的屏幕而非崩溃。
        let orphan = window(5000, 5000)
        let current = DisplayGeometry.current(for: orphan, in: [Self.main, Self.external])
        XCTAssertNotNil(current)
    }

    // MARK: - mappedFrame

    func testMappedFramePreservesRelativePositionOnSameSizeDisplay() {
        let mapped = DisplayGeometry.mappedFrame(
            of: window(100, 200),
            from: Self.main,
            to: Self.external
        )
        // 源屏和目标屏同尺寸：偏移量原样平移 1920。
        XCTAssertEqual(mapped.minX, 2020)
        XCTAssertEqual(mapped.minY, 200)
        XCTAssertEqual(mapped.width, 800)
        XCTAssertEqual(mapped.height, 600)
    }

    func testMappedFrameScalesRelativePositionOnDifferentSizeDisplay() {
        let large = DisplayInfo(
            frame: DisplayFrame(minX: 1920, minY: 0, width: 3840, height: 2160),
            visibleFrame: DisplayFrame(minX: 1920, minY: 0, width: 3840, height: 2160),
            name: "4K"
        )
        // 窗口位于源屏水平 1/2 处 → 映射到目标屏同样 1/2 处。
        let mapped = DisplayGeometry.mappedFrame(of: window(960, 0), from: Self.main, to: large)
        XCTAssertEqual(mapped.minX, 1920 + 1920, accuracy: 0.001)
    }

    func testMappedFrameClampsIntoVisibleFrame() {
        // 窗口贴近源屏右缘，目标屏可见区域右侧有 Dock 偏移，
        // 映射结果不得越过目标可见区域。
        let target = DisplayInfo(
            frame: DisplayFrame(minX: 1920, minY: 0, width: 1920, height: 1080),
            visibleFrame: DisplayFrame(minX: 1920, minY: 25, width: 1920, height: 1035),
            name: "External"
        )
        let mapped = DisplayGeometry.mappedFrame(
            of: window(1120, 400), // 1920 - 800：源屏最右
            from: Self.main,
            to: target
        )
        XCTAssertEqual(mapped.minX, 1920 + 1920 - 800) // 贴目标可见区右缘
        XCTAssertGreaterThanOrEqual(mapped.minY, 25)
    }

    func testMappedFrameClampsYAboveMenuBar() {
        // 带菜单栏的目标屏（visibleFrame.minY = 25），窗口映射后不得进入菜单栏。
        let target = DisplayInfo(
            frame: DisplayFrame(minX: 1920, minY: 0, width: 1920, height: 1080),
            visibleFrame: DisplayFrame(minX: 1920, minY: 25, width: 1920, height: 1055),
            name: "Notched"
        )
        let mapped = DisplayGeometry.mappedFrame(of: window(0, 0), from: Self.main, to: target)
        XCTAssertEqual(mapped.minY, 25)
    }

    func testMappedFramePinsOversizedWindowToVisibleOrigin() {
        // 窗口比目标屏还大：贴可见区域左上角，不越界。
        let small = DisplayInfo(
            frame: DisplayFrame(minX: 1920, minY: 0, width: 500, height: 400),
            visibleFrame: DisplayFrame(minX: 1920, minY: 0, width: 500, height: 400),
            name: "Tiny"
        )
        let mapped = DisplayGeometry.mappedFrame(of: window(0, 0, 1920, 1080), from: Self.main, to: small)
        XCTAssertEqual(mapped.minX, 1920)
        XCTAssertEqual(mapped.minY, 0)
    }

    func testIntersectionArea() {
        let area = DisplayGeometry.intersectionArea(
            of: window(1800, 0),
            with: Self.main.frame
        )
        XCTAssertEqual(area, 120 * 600)
    }
}
