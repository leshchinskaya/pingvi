import Foundation

/// Keep user choices when replacing the original notification registration.
/// Session data and hooks retain their existing Application Support directory.
enum PreferenceMigration {
    static let legacyID = "local.agent-attention.mac"
    static let currentID = "app.pingvi.mac"
    static let marker = "pingviImportedLegacyPreferences"

    static func run(defaults: UserDefaults = .standard, source: String = legacyID, target: String = currentID) {
        var current = defaults.persistentDomain(forName: target) ?? [:]
        guard current[marker] as? Bool != true else { return }
        let legacy = defaults.persistentDomain(forName: source) ?? [:]
        // Existing choices in the new app always take priority, including false.
        current = legacy.merging(current) { _, existing in existing }
        current[marker] = true
        defaults.setPersistentDomain(current, forName: target)
    }
}
