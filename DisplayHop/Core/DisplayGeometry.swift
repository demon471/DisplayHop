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
