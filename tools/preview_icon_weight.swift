import AppKit

// 菜单栏图标"白色纯度"对比：真实 18pt + 3x 放大，模拟紫色玻璃菜单栏。
// 用法：swift tools/preview_icon_weight.swift [输出路径]

struct Option {
    let index: Int
    let symbol: String
    let weight: NSFont.Weight
    let note: String
}

let options: [Option] = [
    .init(index: 1, symbol: "rectangle.on.rectangle.angled", weight: .regular, note: "当前：空心细描边"),
    .init(index: 2, symbol: "rectangle.on.rectangle.angled", weight: .bold, note: "同样式加粗"),
    .init(index: 3, symbol: "rectangle.on.rectangle.angled", weight: .semibold, note: "半粗"),
    .init(index: 4, symbol: "rectangle.on.rectangle", weight: .bold, note: "不倾斜 + 加粗"),
    .init(index: 5, symbol: "square.on.square", weight: .bold, note: "方形双叠 + 加粗"),
    .init(index: 6, symbol: "display.2", weight: .bold, note: "双显示器 + 加粗"),
]

/// 带 .fill 的实心候选（存在才用）。
let filledCandidates = [
    "rectangle.on.rectangle.angled.fill",
    "rectangle.fill.on.rectangle.fill",
    "square.fill.on.square.fill",
    "rectangle.inset.filled.on.rectangle",
]

let menuBarBackground = NSColor(srgbRed: 0.20, green: 0.08, blue: 0.55, alpha: 1)
let lightBackground = NSColor(srgbRed: 0.96, green: 0.94, blue: 0.99, alpha: 1)

/// 用 paletteColors 强制符号按指定颜色渲染（比 isTemplate + 填充色可靠）。
func symbol(_ name: String, weight: NSFont.Weight, size: CGFloat, color: NSColor) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return base.withSymbolConfiguration(config)
}

/// 在指定矩形中央按比例绘制。
func draw(_ image: NSImage, centeredIn rect: NSRect) {
    let s = image.size
    guard s.width > 0, s.height > 0 else { return }
    let scale = min(rect.width / s.width, rect.height / s.height)
    let target = NSRect(
        x: rect.midX - s.width * scale / 2,
        y: rect.midY - s.height * scale / 2,
        width: s.width * scale,
        height: s.height * scale
    )
    image.draw(in: target)
}

var rows: [(title: String, symbolName: String, weight: NSFont.Weight, note: String)] = []
for option in options {
    rows.append((title: "\(option.index)", symbolName: option.symbol, weight: option.weight, note: option.note))
}
var nextIndex = options.count + 1
for name in filledCandidates where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
    rows.append((title: "\(nextIndex)", symbolName: name, weight: .regular, note: "实心填充"))
    nextIndex += 1
}

let rowHeight: CGFloat = 96
let margin: CGFloat = 26
let headerHeight: CGFloat = 72
let width: CGFloat = 760
let height = rowHeight * CGFloat(rows.count) + margin * 2 + headerHeight

let canvas = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
    NSColor.white.setFill()
    rect.fill()

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 19, weight: .semibold),
        .foregroundColor: NSColor.black,
    ]
    "菜单栏图标候选（左：真实 18pt ／ 右：3x 放大）"
        .draw(at: NSPoint(x: margin, y: height - margin - 26), withAttributes: titleAttrs)

    let hintAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11.5),
        .foregroundColor: NSColor(white: 0.45, alpha: 1),
    ]
    "深色条 = 模拟深色菜单栏（图标应为纯白）"
        .draw(at: NSPoint(x: margin, y: height - margin - 46), withAttributes: hintAttrs)

    for (i, row) in rows.enumerated() {
        let y = height - margin - headerHeight - CGFloat(i + 1) * rowHeight

        // 序号
        let idxAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor(white: 0.3, alpha: 1),
        ]
        row.title.draw(at: NSPoint(x: margin, y: y + rowHeight - 34), withAttributes: idxAttrs)

        // 深色菜单栏条（真实尺寸区域 + 放大区域）
        let barDark = NSRect(x: margin + 26, y: y + 30, width: 150, height: 40)
        menuBarBackground.setFill()
        NSBezierPath(roundedRect: barDark, xRadius: 7, yRadius: 7).fill()

        let barLight = NSRect(x: margin + 26, y: y + 76, width: 150, height: 14)
        lightBackground.setFill()
        NSBezierPath(roundedRect: barLight, xRadius: 4, yRadius: 4).fill()

        // 真实 18pt 绘制：深色菜单栏 → 纯白；浅色菜单栏 → 黑色
        if let image = symbol(row.symbolName, weight: row.weight, size: 18, color: .white) {
            draw(image, centeredIn: barDark.insetBy(dx: 40, dy: 8))
        }
        if let image = symbol(row.symbolName, weight: row.weight, size: 13, color: NSColor(white: 0.1, alpha: 1)) {
            draw(image, centeredIn: barLight.insetBy(dx: 58, dy: 1))
        }

        // 3x 放大（同一深色背景，纯白）
        let zoomBox = NSRect(x: margin + 200, y: y + 30, width: 110, height: 60)
        menuBarBackground.setFill()
        NSBezierPath(roundedRect: zoomBox, xRadius: 8, yRadius: 8).fill()
        if let image = symbol(row.symbolName, weight: row.weight, size: 54, color: .white) {
            draw(image, centeredIn: zoomBox.insetBy(dx: 16, dy: 10))
        }

        // 名称与说明
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Menlo", size: 11) ?? NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor(white: 0.2, alpha: 1),
        ]
        (row.symbolName + "  ·  \(row.note)")
            .draw(at: NSPoint(x: margin + 330, y: y + 62), withAttributes: nameAttrs)
    }
    return true
}

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "tools/icon_weight_options.png"

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("render failed"); exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)  rows=\(rows.count)")
for row in rows { print("  \(row.title). \(row.symbolName) [\(row.note)]") }
