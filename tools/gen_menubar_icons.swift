import AppKit
import Foundation

// 菜单栏图标候选对照表生成器。
// 用法：swift tools/gen_menubar_icons.swift [输出路径]
// 默认输出到 tools/menubar_candidates.png

struct Candidate {
    let index: Int
    let label: String
    let symbol: String?      // SF Symbol 名；nil 表示自绘
    let custom: CustomKind?
}

enum CustomKind {
    case twoDisplays        // 两个重叠圆角矩形（呼应 App 图标）
    case twoDisplaysArrow   // 两个圆角矩形 + 箭头
    case displayArrow       // 屏幕 + 箭头
}

let candidates: [Candidate] = [
    .init(index: 1, label: "display.2", symbol: "display.2", custom: nil),
    .init(index: 2, label: "rectangle.on.rectangle", symbol: "rectangle.on.rectangle", custom: nil),
    .init(index: 3, label: "uiwindow.split.2x1", symbol: "uiwindow.split.2x1", custom: nil),
    .init(index: 4, label: "rectangle.split.2x1", symbol: "rectangle.split.2x1", custom: nil),
    .init(index: 5, label: "arrow.left.arrow.right", symbol: "arrow.left.arrow.right", custom: nil),
    .init(index: 6, label: "rectangle.2.swap", symbol: "rectangle.2.swap", custom: nil),
    .init(index: 7, label: "macwindow.on.rectangle", symbol: "macwindow.on.rectangle", custom: nil),
    .init(index: 8, label: "square.split.2x1", symbol: "square.split.2x1", custom: nil),
    .init(index: 9, label: "arrow.triangle.swap", symbol: "arrow.triangle.swap", custom: nil),
    .init(index: 10, label: "rectangle.on.rectangle.angled", symbol: "rectangle.on.rectangle.angled", custom: nil),
    .init(index: 11, label: "ipad.and.arrow.forward", symbol: "ipad.and.arrow.forward", custom: nil),
    .init(index: 12, label: "自绘：双屏重叠", symbol: nil, custom: .twoDisplays),
    .init(index: 13, label: "自绘：双屏+箭头", symbol: nil, custom: .twoDisplaysArrow),
    .init(index: 14, label: "自绘：屏幕+箭头", symbol: nil, custom: .displayArrow),
    .init(index: 15, label: "display", symbol: "display", custom: nil),
]

// MARK: - 自绘模板（单色，符合菜单栏 template image 规范）

func drawCustom(_ kind: CustomKind, in rect: NSRect) {
    NSColor.black.setFill()
    NSColor.black.setStroke()
    let s = rect.width
    let sw = max(1.2, s * 0.075)

    /// 用 destinationOut 把重叠区域真正挖空（template image 必须是透明而不是白色）。
    func knockout(_ path: NSBezierPath) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        ctx.compositingOperation = .destinationOut
        NSColor.black.setFill()
        path.fill()
        ctx.restoreGraphicsState()
    }

    switch kind {
    case .twoDisplays:
        let back = NSRect(x: rect.minX + s * 0.30, y: rect.minY + s * 0.08,
                          width: s * 0.60, height: s * 0.50)
        let backPath = NSBezierPath(roundedRect: back, xRadius: s * 0.10, yRadius: s * 0.10)
        backPath.lineWidth = sw
        backPath.stroke()

        let front = NSRect(x: rect.minX + s * 0.10, y: rect.minY + s * 0.40,
                           width: s * 0.54, height: s * 0.46)
        // 挖空前屏（略扩一圈留出间隙）
        knockout(NSBezierPath(roundedRect: front.insetBy(dx: -sw * 0.9, dy: -sw * 0.9),
                              xRadius: s * 0.11, yRadius: s * 0.11))
        let frontPath = NSBezierPath(roundedRect: front, xRadius: s * 0.10, yRadius: s * 0.10)
        frontPath.lineWidth = sw
        frontPath.stroke()

    case .twoDisplaysArrow:
        let back = NSRect(x: rect.minX + s * 0.34, y: rect.minY + s * 0.10,
                          width: s * 0.56, height: s * 0.44)
        let backPath = NSBezierPath(roundedRect: back, xRadius: s * 0.09, yRadius: s * 0.09)
        backPath.lineWidth = sw
        backPath.stroke()

        let front = NSRect(x: rect.minX + s * 0.08, y: rect.minY + s * 0.46,
                           width: s * 0.50, height: s * 0.42)
        knockout(NSBezierPath(roundedRect: front.insetBy(dx: -sw * 0.9, dy: -sw * 0.9),
                              xRadius: s * 0.10, yRadius: s * 0.10))
        let frontPath = NSBezierPath(roundedRect: front, xRadius: s * 0.09, yRadius: s * 0.09)
        frontPath.lineWidth = sw
        frontPath.stroke()

        // 前屏内部的向右箭头（表示移动到下一屏）
        let ay = rect.minY + s * 0.67
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: rect.minX + s * 0.17, y: ay))
        arrow.line(to: NSPoint(x: rect.minX + s * 0.46, y: ay))
        arrow.lineWidth = sw
        arrow.lineCapStyle = .round
        arrow.stroke()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: rect.minX + s * 0.35, y: ay + s * 0.10))
        head.line(to: NSPoint(x: rect.minX + s * 0.46, y: ay))
        head.line(to: NSPoint(x: rect.minX + s * 0.35, y: ay - s * 0.10))
        head.lineWidth = sw
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.stroke()

    case .displayArrow:
        let screen = NSRect(x: rect.minX + s * 0.06, y: rect.minY + s * 0.28,
                            width: s * 0.54, height: s * 0.46)
        let sp = NSBezierPath(roundedRect: screen, xRadius: s * 0.09, yRadius: s * 0.09)
        sp.lineWidth = sw
        sp.stroke()

        let stand = NSBezierPath()
        stand.move(to: NSPoint(x: rect.minX + s * 0.33, y: rect.minY + s * 0.28))
        stand.line(to: NSPoint(x: rect.minX + s * 0.33, y: rect.minY + s * 0.12))
        stand.move(to: NSPoint(x: rect.minX + s * 0.20, y: rect.minY + s * 0.12))
        stand.line(to: NSPoint(x: rect.minX + s * 0.46, y: rect.minY + s * 0.12))
        stand.lineWidth = sw
        stand.lineCapStyle = .round
        stand.stroke()

        let ay = rect.minY + s * 0.51
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: rect.minX + s * 0.66, y: ay))
        arrow.line(to: NSPoint(x: rect.minX + s * 0.93, y: ay))
        arrow.lineWidth = sw
        arrow.lineCapStyle = .round
        arrow.stroke()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: rect.minX + s * 0.83, y: ay + s * 0.12))
        head.line(to: NSPoint(x: rect.minX + s * 0.94, y: ay))
        head.line(to: NSPoint(x: rect.minX + s * 0.83, y: ay - s * 0.12))
        head.lineWidth = sw
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.stroke()
    }
}

// MARK: - 渲染

func renderIcon(_ candidate: Candidate, size: CGFloat) -> NSImage? {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        if let symbol = candidate.symbol {
            guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else {
                // 当前系统没有该符号：画一个叉占位
                NSColor.systemRed.setStroke()
                let p = NSBezierPath()
                p.move(to: NSPoint(x: rect.minX + 4, y: rect.minY + 4))
                p.line(to: NSPoint(x: rect.maxX - 4, y: rect.maxY - 4))
                p.move(to: NSPoint(x: rect.maxX - 4, y: rect.minY + 4))
                p.line(to: NSPoint(x: rect.minX + 4, y: rect.maxY - 4))
                p.lineWidth = 2
                p.stroke()
                return true
            }
            let config = NSImage.SymbolConfiguration(pointSize: size * 0.68, weight: .regular)
            let sym = base.withSymbolConfiguration(config) ?? base
            let s = sym.size
            let scale = min(size / max(s.width, 1), size / max(s.height, 1))
            let drawRect = NSRect(
                x: rect.midX - s.width * scale / 2,
                y: rect.midY - s.height * scale / 2,
                width: s.width * scale,
                height: s.height * scale
            )
            sym.draw(in: drawRect)
        } else if let custom = candidate.custom {
            drawCustom(custom, in: rect)
        }
        return true
    }
}

// MARK: - 布局

let columns = 3
let cellWidth: CGFloat = 320
let cellHeight: CGFloat = 124
let rows = Int(ceil(Double(candidates.count) / Double(columns)))
let margin: CGFloat = 26
let headerHeight: CGFloat = 56
let canvasWidth = cellWidth * CGFloat(columns) + margin * 2
let canvasHeight = cellHeight * CGFloat(rows) + margin * 2 + headerHeight

let canvas = NSImage(size: NSSize(width: canvasWidth, height: canvasHeight), flipped: false) { rect in
    NSColor.white.setFill()
    rect.fill()

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
        .foregroundColor: NSColor.black,
    ]
    "DisplayHop 菜单栏图标候选（1–15）— 左起第 1 个为菜单栏真实尺寸 18pt"
        .draw(at: NSPoint(x: margin, y: canvasHeight - margin - 26), withAttributes: titleAttrs)

    for (i, candidate) in candidates.enumerated() {
        let col = i % columns
        let row = i / columns
        let x = margin + CGFloat(col) * cellWidth
        let y = canvasHeight - margin - headerHeight - CGFloat(row + 1) * cellHeight

        let box = NSRect(x: x + 6, y: y + 6, width: cellWidth - 12, height: cellHeight - 12)
        NSColor(white: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()

        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor(white: 0.35, alpha: 1),
        ]
        "\(candidate.index)".draw(at: NSPoint(x: box.minX + 12, y: box.maxY - 26), withAttributes: numAttrs)

        var drawX = box.minX + 40
        for size in [CGFloat(18), 32, 64] {
            if let icon = renderIcon(candidate, size: size) {
                icon.draw(in: NSRect(x: drawX, y: box.midY - size / 2 + 4, width: size, height: size))
                drawX += size + 14
            }
        }

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor(white: 0.28, alpha: 1),
        ]
        candidate.label.draw(at: NSPoint(x: box.minX + 12, y: box.minY + 10), withAttributes: labelAttrs)
    }
    return true
}

// MARK: - 保存

let arguments = CommandLine.arguments
let output = arguments.count > 1
    ? arguments[1]
    : URL(fileURLWithPath: "tools/menubar_candidates.png").path

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("render failed")
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output) (\(Int(canvas.size.width))x\(Int(canvas.size.height)))")
