import Foundation
import OSLog

/// 统一日志。用 subsystem 过滤：
///   log show --predicate 'subsystem == "com.johnbebee.DisplayHop"' --last 5m
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.johnbebee.DisplayHop"

    static let core = Logger(subsystem: subsystem, category: "core")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let ax = Logger(subsystem: subsystem, category: "ax")
}
