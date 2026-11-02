import CoreGraphics
import Foundation

// 检查某个 App 的状态栏（菜单栏）图标是否真的注册并可见。
// 用法：swift tools/check_status_item.swift [bundleId 或进程名，默认 com.johnbebee.DisplayHop]
//
// 说明：状态栏项位于 CGWindowLayer == 25。
//   onscreen = 1        → 当前可见
//   onscreen = 0        → 被菜单栏管理工具（Barbee / Ice / Hidden Bar）移到屏幕外
//   x 为很大的负数      → 同样说明被收纳到"隐藏区段"
//
// 注意：App 本地化后窗口 owner 名是本地化名（如"屏跃"），不是英文名，
// 所以这里支持用 bundle id 反查真实的 owner 名。

import AppKit
import CoreGraphics
import Foundation

let argument = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "com.johnbebee.DisplayHop"

/// 把 bundle id 解析成运行中 App 的 owner 名（窗口列表里的名字）。
func resolveOwnerName(from argument: String) -> [String] {
    if argument.contains(".") {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == argument
        }
        let names = running.compactMap(\.localizedName)
        if !names.isEmpty { return names }
        // App 未运行：从 bundle 读本地化名称，便于提示
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: argument),
           let bundle = Bundle(url: url) {
            return [
                bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
                bundle.infoDictionary?["CFBundleDisplayName"] as? String,
                bundle.infoDictionary?["CFBundleName"] as? String,
            ].compactMap { $0 }
        }
        return [argument]
    }
    return [argument]
}

let ownerNames = Set(resolveOwnerName(from: argument))

guard let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
    print("无法读取窗口列表")
    exit(1)
}

/// 状态栏层级。
let statusBarLayer = 25

var matches: [(x: Double, width: Double, height: Double, onscreen: Bool)] = []
for window in windows {
    guard let layer = window[kCGWindowLayer as String] as? Int, layer == statusBarLayer else { continue }
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    guard ownerNames.contains(owner) else { continue }

    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    matches.append((
        x: bounds["X"] as? Double ?? 0,
        width: bounds["Width"] as? Double ?? 0,
        height: bounds["Height"] as? Double ?? 0,
        onscreen: (window[kCGWindowIsOnscreen as String] as? Int ?? 0) == 1
    ))
}

let displayNames = ownerNames.sorted().joined(separator: " / ")

guard !matches.isEmpty else {
    print("✗ 没有找到 \(displayNames) 的状态栏项。App 是否在运行？")
    exit(1)
}

print("找到 \(matches.count) 个 \(displayNames) 的状态栏窗口：")
for match in matches {
    let state = match.onscreen ? "可见" : "被隐藏 / 在屏幕外"
    print(String(format: "  x=%9.1f  %.0fx%.0f  %@", match.x, match.width, match.height, state))
}

if matches.contains(where: \.onscreen) {
    print("\n✓ 至少有一个状态栏图标当前可见。")
} else {
    print("""

    ⚠ 所有状态栏窗口都不在屏幕上。
      常见原因：Barbee / Ice / Hidden Bar 等菜单栏管理工具把它收进了隐藏区段。
      解决办法：在对应工具里把 \(displayNames) 拖到可见区域；
               或者在系统设置中检查是否开启了"自动隐藏菜单栏"。
    """)
}
