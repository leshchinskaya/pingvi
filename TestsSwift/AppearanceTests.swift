import XCTest
import AppKit
@testable import AgentAttention

final class AppearanceTests: XCTestCase {
    func testInterfaceThemePersistenceAndFallback() throws {
        let domain = "PingviThemeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        XCTAssertEqual(AppTheme.saved(in: defaults), .system)
        for theme in AppTheme.allCases {
            defaults.set(theme.rawValue, forKey: "appTheme")
            XCTAssertEqual(AppTheme.saved(in: defaults), theme)
        }
        defaults.set("unknown", forKey: "appTheme")
        XCTAssertEqual(AppTheme.saved(in: defaults), .system)
    }
    func testSystemThemeClearsAppearanceOverride() {
        XCTAssertNil(AppTheme.system.appearance)
        XCTAssertEqual(AppTheme.light.appearance?.bestMatch(from: [.aqua, .darkAqua]), .aqua)
        XCTAssertEqual(AppTheme.dark.appearance?.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
    }
    func testDefaultLightAndDarkPair() {
        XCTAssertEqual(IconAppearance.resolve(mode: "system", manual: nil, light: nil, dark: nil, isDark: false), .ice)
        XCTAssertEqual(IconAppearance.resolve(mode: "system", manual: nil, light: nil, dark: nil, isDark: true), .night)
    }
    func testManualMoodDoesNotChangeWithSystemTheme() {
        for dark in [false, true] { XCTAssertEqual(IconAppearance.resolve(mode: "manual", manual: "Orbit", light: "Ice", dark: "Night", isDark: dark), .orbit) }
    }
    func testIndependentThemeSelections() {
        XCTAssertEqual(IconAppearance.resolve(mode: "system", manual: "Pingvi", light: "Aurora", dark: "Orbit", isDark: false), .aurora)
        XCTAssertEqual(IconAppearance.resolve(mode: "system", manual: "Pingvi", light: "Aurora", dark: "Orbit", isDark: true), .orbit)
    }
    func testUnknownPersistedMoodHasValidFallback() {
        XCTAssertEqual(IconAppearance.resolve(mode: "manual", manual: "removed", light: nil, dark: nil, isDark: false), .ice)
    }
}
