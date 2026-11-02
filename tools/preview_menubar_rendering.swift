import AppKit

// 对比菜单栏图标的三种渲染效果，模拟紫色半透明菜单栏背景。
// 用法：swift tools/preview_menubar_rendering.swift [输出路径]

let symbolName = "rectangle.on.rectangle.angled"
let background = NSColor(srgbRed: 0.20, green: 0.08, blue: 0.55, alpha: 1)

struct Variant {
    let title: String
    let detail: String
    let render: (NSRect) -> Void
}

/// 用指定渲染模式绘制 SF Symbol。
/// AppKit 这边没有直接的 renderingMode，用 hierarchicalColor 模拟分层渲染，
/// 不做颜色配置时按 template（单色）绘制。
func drawSymbol(hierarchical: Bool, in rect: NSRect, size: CGFloat) {
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return }
    var config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    if hierarchical {
        config = config.applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
    }
    guard let symbol = base.withSymbolConfiguration(config) else { return }
    let s = symbol.size
    let scale = min(rect.width / max(s.width, 1), rect.height / max(s.height, 1))
    let target = NSRect(
        x: rect.midX - s.width * scale / 2,
        y: rect.midY - s.height * scale / 2,
        width: s.width * scale,
        height: s.height * scale
    )
    // 菜单栏图标实际用前景色（深色菜单栏 = 白色）
    NSColor.white.set()
    symbol.isTemplate = true
    symbol.draw(in: target)
}

let variants: [Variant] = [
    Variant(
        title: "A. hierarchical（旧）",
        detail: "系统默认：次要图层降透明度，叠在彩色玻璃上发紫",
        render: { rect in drawSymbol(hierarchical: true, in: rect, size: rect.height * 0.72) }
    ),
    Variant(
        title: "B. monochrome（新）",
        detail: "两层统一纯白，菜单栏里始终是白色描边",
        render: { rect in drawSymbol(hierarchical: false, in: rect, size: rect.height * 0.72) }
    ),
]

let cellW: CGFloat = 420
let cellH: CGFloat = 150
let margin: CGFloat = 26
let headerH: CGFloat = 64
let width = cellW + margin * 2
let height = cellH * CGFloat(variants.count) + margin * 2 + headerH

let canvas = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
    NSColor.white.setFill()
    rect.fill()

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 19, weight: .semibold),
        .foregroundColor: NSColor.black,
    ]
    "菜单栏图标渲染对比（模拟紫色玻璃菜单栏）"
        .draw(at: NSPoint(x: margin, y: height - margin - 26), withAttributes: titleAttrs)

    for (i, variant) in variants.enumerated() {
        let y = height - margin - headerH - CGFloat(i + 1) * cellH

        // 菜单栏模拟条
        let bar = NSRect(x: margin, y: y + 54, width: cellW, height: 44)
        background.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 8, yRadius: 8).fill()

        // 图标区域（菜单栏真实尺寸 18pt 放大 2 倍展示）
        let iconBox = NSRect(x: bar.minX + 24, y: bar.minY + 6, width: 44, height: 32)
        variant.render(iconBox)

        // 右侧对照：系统单层图标作为白色基准
        if let ref = NSImage(systemSymbolName: "display", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)) {
            ref.isTemplate = true
            NSColor.white.set()
            let s = ref.size
            ref.draw(in: NSRect(x: bar.maxX - s.width - 24, y: bar.midY - s.height / 2,
                                width: s.width, height: s.height))
        }

        let titleAttrs2: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(white: 0.15, alpha: 1),
        ]
        variant.title.draw(at: NSPoint(x: margin, y: y + 32), withAttributes: titleAttrs2)

        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor(white: 0.4, alpha: 1),
        ]
        variant.detail.draw(at: NSPoint(x: margin, y: y + 12), withAttributes: detailAttrs)
    }
    return true
}

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "tools/menubar_rendering.png"

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("render failed"); exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
