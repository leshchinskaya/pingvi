import XCTest
@testable import AgentAttention

final class WorkspaceAttachmentTests: XCTestCase {
    func testWorkspacePersistenceAndDeletionPreservesSession() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(storageDirectory: directory, notificationsEnabled: false)
        let session = Session(id: "test", title: "Task", project: "", agent: "codex", source: "herdr", status: "working", question: "", options: [], token: "token", canReply: false, kind: "screen", updated: 0, target: [:], detail: "", fields: [])
        store.local.sessions = [session]
        store.saveWorkspace(name: "  Release  ")
        let id = try XCTUnwrap(store.workspaces.first?.id)
        store.assign(session, to: id)
        store.saveWorkspace(id: id, name: "Release 2")
        let restored = Store(storageDirectory: directory, notificationsEnabled: false)
        XCTAssertEqual(restored.workspaces.first?.name, "Release 2")
        XCTAssertEqual(restored.workspaceID(session), id)
        restored.deleteWorkspace(id)
        XCTAssertNil(restored.workspaceID(session))
        XCTAssertEqual(restored.local.sessions.count, 1)
        XCTAssertTrue(Store(storageDirectory: directory, notificationsEnabled: false).workspaces.isEmpty)
    }

    func testOldStateDecodesWithoutWorkspaces() throws {
        let data = try JSONEncoder().encode(LocalState())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "workspaces")
        json.removeValue(forKey: "workspaceAssignments")
        let decoded = try JSONDecoder().decode(LocalState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.workspaces)
    }

    func testAttachmentsPreserveUnusualPathsAndAvoidDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("screen \"one\"\n$two.png")
        try Data([1, 2]).write(to: file)
        let line = try AttachmentReference.line(for: file)
        let encodedPath = String(line.dropFirst(AttachmentReference.prefix.count))
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: Data(encodedPath.utf8)), file.path)
        let draft = try AttachmentReference.adding([file, file], to: "Проверь")
        XCTAssertEqual(draft, "Проверь\n" + line)
        XCTAssertEqual(try AttachmentReference.adding([file], to: draft), draft)
        XCTAssertNoThrow(try AttachmentReference.validate(in: "Вариант — " + draft))
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try AttachmentReference.validate(in: draft))
        XCTAssertThrowsError(try AttachmentReference.adding([directory], to: draft))
        XCTAssertThrowsError(try AttachmentReference.adding([directory.appendingPathComponent("missing")], to: draft))
    }
}
