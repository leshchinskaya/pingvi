import XCTest
@testable import Pingvi

final class MobileAppearanceTests: XCTestCase {
    func testThemeRawValuesRemainCompatibleWithMacSettings() {
        XCTAssertEqual(MobileTheme.allCases.map(\.rawValue), ["system", "light", "dark"])
    }

    func testPrimaryAndAlternateIconNamesMatchAssetCatalog() {
        XCTAssertNil(MobileIconMood.ice.alternateIconName)
        XCTAssertEqual(MobileIconMood.night.alternateIconName, "Night")
        XCTAssertEqual(MobileIconMood.aurora.alternateIconName, "Aurora")
        XCTAssertEqual(MobileIconMood.orbit.alternateIconName, "Orbit")
        XCTAssertEqual(MobileIconMood.classic.alternateIconName, "Classic")
    }

    func testUnknownAlternateIconFallsBackToIce() {
        XCTAssertEqual(MobileIconMood.resolve(alternateIconName: nil), .ice)
        XCTAssertEqual(MobileIconMood.resolve(alternateIconName: "removed"), .ice)
        XCTAssertEqual(MobileIconMood.resolve(alternateIconName: "Orbit"), .orbit)
    }
}
