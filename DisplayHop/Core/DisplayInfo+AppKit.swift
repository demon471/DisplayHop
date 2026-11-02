import AppKit

// MARK: - AppKit ↔ CG 坐标转换
//
// NSScreen 使用“主屏幕左下角为原点”的坐标系，
// AX API 使用“主屏幕左上角为原点”的坐标系。
// 这里统一转换到 CG 空间，供 DisplayGeometry 的纯函数使用。

extension NSScreen {
    /// 主屏幕（origin == .zero）的 AppKit frame，用作两套坐标系的桥。
    private static var primaryAppKitFrame: CGRect {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame ?? .zero
    }

    /// 完整 frame，转换到 CG 全局坐标（左上角原点）。
    var cgFrame: CGRect {
        Self.convertToCG(frame)
    }

    /// 可用区域（排除菜单栏和 Dock），转换到 CG 全局坐标。
    var cgVisibleFrame: CGRect {
        Self.convertToCG(visibleFrame)
    }

    private static func convertToCG(_ appKitFrame: CGRect) -> CGRect {
        let primaryHeight = primaryAppKitFrame.height
        return CGRect(
            x: appKitFrame.origin.x,
            y: primaryHeight - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }
}

extension DisplayInfo {
    init(screen: NSScreen) {
        self.init(
            frame: DisplayFrame(screen.cgFrame),
            visibleFrame: DisplayFrame(screen.cgVisibleFrame),
            name: screen.localizedName
        )
    }
}

extension DisplayFrame {
    init(_ rect: CGRect) {
        self.init(minX: rect.minX, minY: rect.minY, width: rect.width, height: rect.height)
    }
}

extension WindowFrame {
    init(_ rect: CGRect) {
        self.init(minX: rect.minX, minY: rect.minY, width: rect.width, height: rect.height)
    }

    var cgRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}
