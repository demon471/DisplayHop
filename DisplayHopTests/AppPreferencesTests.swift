import XCTest
@testable import DisplayHop

/// 偏好设置的默认值与持久化。
/// 这些开关直接决定 App 有没有可见入口，逻辑不能错。
@MainActor
final class AppPreferencesTests: XCTestCase {

    /// 每个用例独立的 UserDefaults 域，避免互相污染。
    private func makeDefaults(suiteName: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultsShowBothIconsOnFirstLaunch() {
        let defaults = makeDefaults(suiteName: "test.defaults.firstLaunch")
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertTrue(preferences.showMenuBarIcon)
        XCTAssertTrue(preferences.showDockIcon)
        XCTAssertTrue(preferences.hasVisibleEntryPoint)
    }

    func testPersistsBothSwitchesIndependently() {
        let suite = "test.defaults.persist"
        let defaults = makeDefaults(suiteName: suite)
        let preferences = AppPreferences(defaults: defaults)

        preferences.showMenuBarIcon = false
        preferences.showDockIcon = true

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.showMenuBarIcon)
        XCTAssertTrue(reloaded.showDockIcon)
    }

    func testDockIconCanBeHiddenWhileMenuBarStaysVisible() {
        let defaults = makeDefaults(suiteName: "test.defaults.dockOnly")
        let preferences = AppPreferences(defaults: defaults)

        preferences.showDockIcon = false

        XCTAssertTrue(preferences.showMenuBarIcon)
        XCTAssertFalse(preferences.showDockIcon)
        // 还有菜单栏入口，不算无入口状态
        XCTAssertTrue(preferences.hasVisibleEntryPoint)
    }

    func testHidingBothIconsMeansNoEntryPoint() {
        let defaults = makeDefaults(suiteName: "test.defaults.noEntry")
        let preferences = AppPreferences(defaults: defaults)

        preferences.showMenuBarIcon = false
        preferences.showDockIcon = false

        XCTAssertFalse(preferences.hasVisibleEntryPoint)
    }
}
