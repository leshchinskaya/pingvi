import AppKit
import XCTest
@testable import AgentAttention

final class ProductivityTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func session(_ id: String, status: String = "done") -> Session {
        Session(id: id, title: id, project: "/project", agent: "codex", source: "herdr", status: status, question: "", options: [], token: id, canReply: false, kind: "screen", updated: 1, target: [:], detail: "", fields: [])
    }
    func testNotesPersistAreIsolatedAndCanBeCleared() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(storageDirectory: dir, notificationsEnabled: false)
        let one = session("one"), two = session("two")
        store.local.sessions = [one, two]
        try store.setNote("Проверить миграцию\nПосле тестов", for: one)
        let restored = Store(storageDirectory: dir, notificationsEnabled: false)
        XCTAssertEqual(restored.note(one), "Проверить миграцию\nПосле тестов")
        XCTAssertEqual(restored.note(two), "")
        XCTAssertTrue(restored.local.drafts.isEmpty)
        try restored.setNote("  \n", for: one)
        XCTAssertEqual(Store(storageDirectory: dir, notificationsEnabled: false).note(one), "")
    }
    func testOldStateWithoutNotesDecodesAndFailedSaveDoesNotLoseNote() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(LocalState())) as? [String: Any])
        object.removeValue(forKey: "notes")
        XCTAssertNil(try JSONDecoder().decode(LocalState.self, from: JSONSerialization.data(withJSONObject: object)).notes)
        let dir = directory(); try Data().write(to: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(storageDirectory: dir, notificationsEnabled: false)
        store.local.notes = ["one": "Keep"]
        XCTAssertThrowsError(try store.setNote("Replace", for: session("one")))
        XCTAssertEqual(store.note(session("one")), "Keep")
    }
    func testTemplatesCreateEditDeleteAndPreserveDraft() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let templates = ReplyTemplates(storageDirectory: dir)
        try templates.save(id: nil, title: " My template ", text: "Check changes")
        let added = try XCTUnwrap(templates.items.last)
        XCTAssertEqual(added.title, "My template")
        try templates.save(id: added.id, title: "Updated", text: "Updated body")
        let restored = ReplyTemplates(storageDirectory: dir)
        XCTAssertEqual(restored.items.last?.text, "Updated body")
        XCTAssertEqual(ReplyTemplates.inserting("Template", into: "Existing"), "Existing\n\nTemplate")
        for item in restored.items { try restored.delete(item.id) }
        XCTAssertTrue(ReplyTemplates(storageDirectory: dir).items.isEmpty, "Deleting defaults must survive restart")
    }
    func testInvalidTemplateAndFailedPersistenceKeepExistingItems() throws {
        let dir = directory(); try Data().write(to: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        let templates = ReplyTemplates(storageDirectory: dir), original = templates.items
        XCTAssertThrowsError(try templates.save(id: nil, title: " ", text: "x"))
        XCTAssertThrowsError(try templates.save(id: nil, title: "x", text: "x"))
        XCTAssertEqual(templates.items, original)
    }
    func testClipboardImageStoredAsUniqueReadablePNGAndInvalidImageDoesNotWrite() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let tiff = try XCTUnwrap(bitmap.tiffRepresentation)
        let one = try ClipboardImage.save(tiff, directory: dir)
        let two = try ClipboardImage.save(tiff, directory: dir)
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(Array(try Data(contentsOf: one).prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let draft = try AttachmentReference.adding([one], to: "Look at this")
        XCTAssertTrue(draft.hasPrefix("Look at this\n"))
        XCTAssertNoThrow(try AttachmentReference.validate(in: draft))
        let permissions = try FileManager.default.attributesOfItem(atPath: one.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        XCTAssertThrowsError(try ClipboardImage.save(Data("bad".utf8), directory: dir))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 2)
    }
    func testResultOverviewFiltersWorkspaceAndDoesNotMarkReadUntilRequested() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(storageDirectory: dir, notificationsEnabled: false)
        store.local.sessions = [session("one"), session("two", status: "viewed"), session("busy", status: "working"), session("excluded")]
        store.local.excluded = ["excluded"]
        store.local.workspaceAssignments = ["one": "workspace"]
        XCTAssertEqual(CompletedResults.sessions(in: store, workspace: "all", includeViewed: false).map(\.id), ["one"])
        XCTAssertEqual(CompletedResults.sessions(in: store, workspace: "ungrouped", includeViewed: true).map(\.id), ["two"])
        XCTAssertEqual(store.local.sessions[0].status, "done")
        store.markViewed(session("one"))
        XCTAssertTrue(CompletedResults.sessions(in: store, workspace: "workspace", includeViewed: false).isEmpty)
    }
    func testResultsDoNotBorrowAnswerFromPreviousTurn() {
        let old = ChatMessage(id: "old", role: "assistant", text: "Old", state: "received")
        let user = ChatMessage(id: "user", role: "user", text: "New task", state: "received")
        let answer = ChatMessage(id: "new", role: "assistant", text: "New result", state: "received")
        XCTAssertNil(CompletedResults.lastAnswer(in: [old, user]))
        XCTAssertEqual(CompletedResults.lastAnswer(in: [old, user, answer])?.id, "new")
    }
}
