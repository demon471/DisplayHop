import KeyboardShortcuts
import SwiftUI

// MARK: - 设置窗口
//
// 不用 SwiftUI 的 TabView：
// 当 TabView 被放进普通 NSWindow 时，macOS 会把它渲染成工具栏分段控件，
// 该样式只显示文字、丢弃 SF Symbol 图标，而且会占掉标题栏。
// 这里自绘经典 macOS 设置窗口的页签栏（图标在上、文字在下，居中），
// 保证图标可见且标题栏正常显示窗口标题。

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .shortcuts

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $selectedTab)

            Divider()

            Group {
                switch selectedTab {
                case .shortcuts: ShortcutsTab()
                case .general: GeneralTab()
                case .diagnostics: DiagnosticsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 480)
    }
}

// MARK: - 页签定义

enum SettingsTab: String, CaseIterable, Identifiable {
    case shortcuts
    case general
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortcuts: NSLocalizedString("快捷键", comment: "设置页签")
        case .general: NSLocalizedString("通用", comment: "设置页签")
        case .diagnostics: NSLocalizedString("诊断", comment: "设置页签")
        }
    }

    var symbol: String {
        switch self {
        case .shortcuts: "keyboard"
        case .general: "gearshape"
        case .diagnostics: "stethoscope"
        }
    }
}

// MARK: - 经典页签栏

private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 16, weight: .regular))
                            .frame(height: 18)
                        Text(tab.title)
                            .font(.system(size: 11))
                    }
                    .frame(width: 72, height: 48)
                    .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selection == tab ? Color.primary.opacity(0.09) : Color.clear)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

// MARK: 快捷键

private struct ShortcutsTab: View {
    var body: some View {
        Form {
            Section("窗口跨屏移动") {
                LabeledContent("移动到下一屏") {
                    KeyboardShortcuts.Recorder(for: .moveToNextDisplay)
                }
                LabeledContent("移动到上一屏") {
                    KeyboardShortcuts.Recorder(for: .moveToPreviousDisplay)
                }
            }
            Section {
                Text("移动的是当前聚焦的窗口，并保持其在屏幕中的相对位置。全屏窗口会先退出全屏再移动。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: 通用

private struct GeneralTab: View {
    @ObservedObject private var preferences = AppPreferences.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var accessibilityGranted = AccessibilityPermission.isGranted
    @State private var refreshTimer: Timer?

    var body: some View {
        Form {
            Section("菜单栏") {
                Toggle("显示菜单栏图标", isOn: $preferences.showMenuBarIcon)
                if !preferences.showMenuBarIcon {
                    Text("图标已隐藏。重新打开屏跃时会自动弹出本设置窗口，可在这里恢复显示。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("启动") {
                Toggle("登录时启动屏跃", isOn: launchAtLoginBinding)
            }

            Section("权限") {
                LabeledContent("辅助功能") {
                    if accessibilityGranted {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Button("前往系统设置") {
                            AccessibilityPermission.openSystemPane()
                        }
                    }
                }
                Text("需要辅助功能权限才能读取和移动其他应用的窗口。在系统设置中勾选屏跃后，这里会自动更新。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityGranted = AccessibilityPermission.isGranted
            startPolling()
        }
        .onDisappear { refreshTimer?.invalidate() }
    }

    /// 轮询授权状态：用户在系统设置勾选后无需手动刷新界面。
    /// （AX 授权没有系统通知，轮询是矩形、Wins 等工具的通行做法。）
    private func startPolling() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                accessibilityGranted = AccessibilityPermission.isGranted
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                LaunchAtLogin.setEnabled(newValue)
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        )
    }
}

// MARK: 诊断

private struct DiagnosticsTab: View {
    @ObservedObject private var appState = AppDelegate.sharedAppState
    @State private var accessibilityGranted = AccessibilityPermission.isGranted
    @State private var refreshTimer: Timer?

    var body: some View {
        Form {
            Section("权限") {
                LabeledContent("辅助功能") {
                    if accessibilityGranted {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Label("未授权", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .labelStyle(.titleAndIcon)
                    }
                }
                Text("辅助功能权限与「App 二进制」绑定。重新构建或重新安装后需要重新授权，否则快捷键会触发但窗口不会移动。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("快捷键") {
                LabeledContent("移动到下一屏") {
                    Text(KeyboardShortcuts.Name.moveToNextDisplay.shortcut?.description ?? "未设置")
                        .font(.body.monospaced())
                }
                LabeledContent("移动到上一屏") {
                    Text(KeyboardShortcuts.Name.moveToPreviousDisplay.shortcut?.description ?? "未设置")
                        .font(.body.monospaced())
                }
            }

            Section("上次操作") {
                LabeledContent("结果") {
                    Text(appState.lastOutcome.map(Self.describe) ?? "尚未执行")
                        .foregroundStyle(appState.lastOutcome == .moved(displayName: "") ? Color.green : Color.secondary)
                }
                Text("执行一次移动快捷键后，这里会显示结果。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("显示器") {
                LabeledContent("数量") { Text("\(NSScreen.screens.count)") }
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                    LabeledContent("屏幕 \(index + 1)") {
                        Text("\(screen.localizedName)  \(Int(screen.frame.width))×\(Int(screen.frame.height))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            accessibilityGranted = AccessibilityPermission.isGranted
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                Task { @MainActor in accessibilityGranted = AccessibilityPermission.isGranted }
            }
        }
        .onDisappear { refreshTimer?.invalidate() }
    }

    private static func describe(_ outcome: MoveOutcome) -> String {
        switch outcome {
        case .moved(let displayName): return "已移动到 \(displayName)"
        case .noFocusedWindow: return "没有聚焦窗口"
        case .notAuthorized: return "辅助功能未授权"
        case .singleDisplay: return "只有一块屏幕"
        case .failed: return "移动失败（AX 写入失败）"
        }
    }
}
