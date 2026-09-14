import XCTest
@testable import AgentAttention

final class DataSettingsTests: XCTestCase {
    func testChatCleanupPersistsAndKeepsAgentChoice() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = ChatPreferences(storageDirectory: directory)
        preferences.saved.drafts = ["one": "secret"]
        preferences.saved.firstMessage = "new secret"
        preferences.saved.recentProjects = ["/private/project"]
        preferences.saved.project = "/private/project"
        preferences.saved.agent = "claude"
        try preferences.clearDrafts()
        let restored = ChatPreferences(storageDirectory: directory)
        XCTAssertTrue(restored.saved.drafts.isEmpty)
        XCTAssertTrue(restored.saved.firstMessage.isEmpty)
        XCTAssertTrue(restored.saved.recentProjects.isEmpty)
        XCTAssertEqual(restored.saved.recentProjectsInitialized, true)
        XCTAssertTrue(restored.saved.project.isEmpty)
        XCTAssertEqual(restored.saved.agent, "claude")
    }
    func testFailedChatCleanupKeepsDraftInMemory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferences = ChatPreferences(storageDirectory: directory)
        preferences.saved.drafts = ["one": "keep"]
        XCTAssertThrowsError(try preferences.clearDrafts())
        XCTAssertEqual(preferences.saved.drafts["one"], "keep")
    }
    func testQuestionCleanupPreservesDeliveryState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var state = LocalState()
        state.uncertain = ["session": "question"]
        try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("state.json"))
        let store = Store(storageDirectory: directory, notificationsEnabled: false)
        store.local.drafts = ["question": ["choice": "A"]]
        store.local.snoozes = ["question": 100]
        store.local.seen = ["session"]
        try store.clearQuestionDrafts()
        let restored = Store(storageDirectory: directory, notificationsEnabled: false)
        XCTAssertTrue(restored.local.drafts.isEmpty)
        XCTAssertEqual(restored.local.uncertain?["session"], "question")
        XCTAssertEqual(restored.local.snoozes["question"], 100)
        XCTAssertTrue(restored.local.seen.contains("session"))
    }
}
