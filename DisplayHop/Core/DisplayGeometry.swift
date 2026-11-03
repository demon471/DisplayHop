import Foundation

// MARK: - 坐标约定
//
// 所有几何计算统一使用 CG 全局坐标（主屏幕左上角为原点，y 向下），
// 这也是辅助功能 API（AXPosition/AXSize）使用的坐标空间。
// AppKit 的 NSScreen（左下角原点）在 `DisplayInfo+AppKit.swift` 中完成转换。
// 本文件内所有计算均为纯函数，可脱离真实显示器进行单元测试。

/// 窗口在全局坐标中的位置与尺寸。
struct WindowFrame: Equatable, Sendable {
    var minX: Double
    var minY: Double
    var width: Double
    var height: Double

    var maxX: Double { minX + width }
    var maxY: Double { minY + height }
}

/// 显示器的 frame（同一坐标空间）。
struct DisplayFrame: Equatable, Sendable {
    var minX: Double
    var minY: Double
    var width: Double
    var height: Double

    var maxX: Double { minX + width }
    var maxY: Double { minY + height }
}

/// 一块显示器的几何描述。
struct DisplayInfo: Equatable, Sendable {
    /// 完整 frame（含菜单栏区域）。
    var frame: DisplayFrame
    /// 可用区域（排除菜单栏和 Dock，即 NSScreen.visibleFrame）。
    var visibleFrame: DisplayFrame
    /// 系统设置中显示的名称，如 "Studio Display"。
    var name: String
}

/// 跨屏移动所需的所有几何计算。
enum DisplayGeometry {
    /// 按“从左到右、从上到下”排序显示器，
    /// 与系统设置 > 显示器 > 排列 中的方向一致。
    static func ordered(_ displays: [DisplayInfo]) -> [DisplayInfo] {
        displays.sorted { lhs, rhs in
            if lhs.frame.minX != rhs.frame.minX {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.minY < rhs.frame.minY
        }
    }

    /// 找出窗口所在的显示器：与窗口重叠面积最大的一块。
    /// 窗口横跨两块屏幕时，归属面积更大的那块。
    static func current(for window: WindowFrame, in displays: [DisplayInfo]) -> DisplayInfo? {
        guard !displays.isEmpty else { return nil }
        return displays.max {
            intersectionArea(of: window, with: $0.frame)
                < intersectionArea(of: window, with: $1.frame)
        }
    }

    static func intersectionArea(of window: WindowFrame, with display: DisplayFrame) -> Double {
        let overlapX = min(window.maxX, display.maxX) - max(window.minX, display.minX)
        let overlapY = min(window.maxY, display.maxY) - max(window.minY, display.minY)
        return max(0, overlapX) * max(0, overlapY)
    }

    /// 判断窗口是否处于「铺满整屏」状态。
    ///
    /// 系统「填充」动作会在四周留 8pt 边距，而本 App 要的是零边距，
    /// 所以这里只用几何判断：窗口是否几乎贴满屏幕可见区。
    /// 容忍度放宽到 45pt，覆盖系统填充的 8pt 以及外屏菜单栏保留区。
    static func isFilled(
        _ window: WindowFrame,
        in display: DisplayInfo,
        tolerance: Double = 45
    ) -> Bool {
        let visible = display.visibleFrame
        guard visible.width > 0, visible.height > 0 else { return false }
        return abs(window.width - visible.width) <= tolerance
            && abs(window.height - visible.height) <= tolerance
    }

    /// 零边距铺满目标屏：位置取屏幕原点，尺寸取整屏。
    /// 高度若超出系统允许范围（菜单栏保留区），会被系统自动钳制，
    /// 实测结果与系统最大化的表现一致且无边距。
    static func fillFrame(in display: DisplayInfo) -> WindowFrame {
        WindowFrame(
            minX: display.frame.minX,
            minY: display.frame.minY,
            width: display.frame.width,
            height: display.frame.height
        )
    }

    /// 把窗口尺寸限制在目标屏可见区域内（仅当装不下时缩小）。
    /// 跨到更小的屏幕时，避免窗口超出屏幕边界。
    static func fittingSize(_ window: WindowFrame, in display: DisplayInfo) -> WindowFrame {
        let visible = display.visibleFrame
        var result = window
        if visible.width > 0, window.width > visible.width {
            result.width = visible.width
        }
        if visible.height > 0, window.height > visible.height {
            result.height = visible.height
        }
        return result
    }

    /// 将窗口从 `source` 屏映射到 `target` 屏：
    /// 1. 保持窗口在源屏幕 frame 内的相对位置（比例不变，屏幕尺寸不同也居中归位）；
    /// 2. 结果夹紧到目标屏幕的可见区域内，保证不会跑到菜单栏或 Dock 底下，
    ///    窗口比目标屏幕还大时贴靠在可见区域左上角。
    static func mappedFrame(
        of window: WindowFrame,
        from source: DisplayInfo,
        to target: DisplayInfo
    ) -> WindowFrame {
        let relativeX = source.frame.width > 0
            ? (window.minX - source.frame.minX) / source.frame.width
            : 0
        let relativeY = source.frame.height > 0
            ? (window.minY - source.frame.minY) / source.frame.height
            : 0

        var x = target.frame.minX + relativeX.clamped(to: 0...1) * target.frame.width
        var y = target.frame.minY + relativeY.clamped(to: 0...1) * target.frame.height

        let visible = target.visibleFrame
        let maxX = max(visible.minX, visible.maxX - window.width)
        let maxY = max(visible.minY, visible.maxY - window.height)
        x = min(max(x, visible.minX), maxX)
        y = min(max(y, visible.minY), maxY)

        return WindowFrame(minX: x, minY: y, width: window.width, height: window.height)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
