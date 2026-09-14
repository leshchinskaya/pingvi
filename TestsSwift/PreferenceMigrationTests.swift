import XCTest
@testable import AgentAttention

final class PreferenceMigrationTests: XCTestCase {
    func testMigrationPreservesChoicesWithoutChangingSource() {
        let defaults = UserDefaults.standard
        let source = "test.pingvi.source." + UUID().uuidString
        let target = "test.pingvi.target." + UUID().uuidString
        defer { defaults.removePersistentDomain(forName: source); defaults.removePersistentDomain(forName: target) }
        defaults.setPersistentDomain(["dock": false, "questionNotifications": false, "terminal": true, "iconMode": "manual", "iconManual": "Night"], forName: source)
        PreferenceMigration.run(defaults: defaults, source: source, target: target)
        let imported = defaults.persistentDomain(forName: target)!
        XCTAssertEqual(imported["dock"] as? Bool, false)
        XCTAssertEqual(imported["questionNotifications"] as? Bool, false)
        XCTAssertEqual(imported["terminal"] as? Bool, true)
        XCTAssertEqual(imported["iconManual"] as? String, "Night")
        XCTAssertNil(defaults.persistentDomain(forName: source)?[PreferenceMigration.marker])
    }

    func testMigrationDoesNotOverwriteNewPreferencesOrReimportOnRestart() {
        let defaults = UserDefaults.standard
        let source = "test.pingvi.source." + UUID().uuidString
        let target = "test.pingvi.target." + UUID().uuidString
        defer { defaults.removePersistentDomain(forName: source); defaults.removePersistentDomain(forName: target) }
        defaults.setPersistentDomain(["terminal": true, "iconManual": "Ice"], forName: source)
        defaults.setPersistentDomain(["terminal": false, "iconManual": "Orbit"], forName: target)
        PreferenceMigration.run(defaults: defaults, source: source, target: target)
        XCTAssertEqual(defaults.persistentDomain(forName: target)?["terminal"] as? Bool, false)
        XCTAssertEqual(defaults.persistentDomain(forName: target)?["iconManual"] as? String, "Orbit")
        defaults.setPersistentDomain([PreferenceMigration.marker: true, "iconManual": "Aurora"], forName: target)
        PreferenceMigration.run(defaults: defaults, source: source, target: target)
        XCTAssertEqual(defaults.persistentDomain(forName: target)?["iconManual"] as? String, "Aurora")
        XCTAssertNil(defaults.persistentDomain(forName: target)?["terminal"])
    }
}
