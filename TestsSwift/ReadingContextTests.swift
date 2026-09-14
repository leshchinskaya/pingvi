import XCTest
@testable import AgentAttention

final class ReadingContextTests: XCTestCase {
    func testAppendedAndRollingTerminalContextKeepOnlyExactOldTextCollapsed() {
        let appended = ReadingContext(text: "Old context\nNew answer", previous: "Old context")
        XCTAssertEqual(appended.earlier, "Old context")
        XCTAssertEqual(appended.new, "New answer")
        let footer = ReadingContext(text: "Project context\nAgent response\nNew question?", previous: "Project context\nAgent response\nOld footer")
        XCTAssertEqual(footer.new, "New question?")
        let rolling = ReadingContext(text: "Line two\nLine three\nNew question?", previous: "Line one\nLine two\nLine three")
        XCTAssertEqual(rolling.earlier, "Line two\nLine three")
        XCTAssertEqual(rolling.new, "New question?")
    }
    func testChangedOrAmbiguousContextRemainsFullyVisible() {
        for previous in ["Different text", "Old line\nRepeated heading", "Old\n\n"] {
            let text = "Repeated heading\nNew action"
            let context = ReadingContext(text: text, previous: previous)
            XCTAssertEqual(context.new, text)
            XCTAssertTrue(context.earlier.isEmpty)
        }
    }
    func testNewConversationOpensAtFirstMessageAfterLastReply() {
        let messages = history()
        XCTAssertEqual(ChatReading.initialTarget(in: messages, bookmark: nil), "new-1")
        XCTAssertEqual(ChatReading.firstNew(in: messages), "new-1")
    }
    func testSameReplyRestoresReadingButAnotherReplyInvalidatesOldPosition() {
        let bookmark = ChatReadingBookmark(replyID: "reply", visibleID: "new-2")
        XCTAssertEqual(ChatReading.initialTarget(in: history(), bookmark: bookmark), "new-2")
        let newer = history() + [message("reply-2", role: "user"), message("answer-2")]
        XCTAssertEqual(ChatReading.initialTarget(in: newer, bookmark: bookmark), "answer-2")
    }
    func testMissingBookmarkAndUncertainSendDoNotHideNewMessages() {
        let messages = history() + [message("uncertain", role: "user", state: "uncertain")]
        XCTAssertEqual(ChatReading.firstNew(in: messages), "new-1")
        XCTAssertEqual(ChatReading.initialTarget(in: messages, bookmark: .init(replyID: "reply", visibleID: "removed")), "new-1")
        XCTAssertNil(ChatReading.initialTarget(in: [], bookmark: nil))
    }
    func testQuestionReplyBoundaryWorksWithoutUserMessageInTranscript() {
        XCTAssertEqual(ChatReading.firstNew(in: history(), afterMessage: "new-1"), "new-2")
        XCTAssertEqual(ChatReading.firstNew(in: history(), afterMessage: "removed"), "new-1")
    }
    func testReadingBookmarksSurviveRestartAndOldPreferencesDecode() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let preferences = ChatPreferences(storageDirectory: dir)
        preferences.saved.reading = ["session": .init(replyID: "reply", visibleID: "new-2")]
        preferences.save()
        XCTAssertEqual(ChatPreferences(storageDirectory: dir).saved.reading?["session"]?.visibleID, "new-2")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences.saved)) as? [String: Any])
        object.removeValue(forKey: "reading"); object.removeValue(forKey: "replyBoundaries")
        let old = try JSONDecoder().decode(ChatPreferences.Saved.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.reading)
    }
    private func history() -> [ChatMessage] {
        [message("old"), message("reply", role: "user"), message("new-1"), message("new-2")]
    }
    private func message(_ id: String, role: String = "assistant", state: String = "received") -> ChatMessage {
        ChatMessage(id: id, role: role, text: id, state: state)
    }
}
