import XCTest
@testable import AgentAttention

final class ConversationSearchTests: XCTestCase {
    func testSearchFindsRussianTextAndPathsInBothRoles() {
        let messages = [
            ChatMessage(id: "1", role: "user", text: "Проверь МИГРАЦИЮ в db/schema.sql", state: "received"),
            ChatMessage(id: "2", role: "assistant", text: "В db/schema.sql обнаружена ошибка", state: "received"),
            ChatMessage(id: "3", role: "assistant", text: "Готово", state: "received")
        ]
        XCTAssertEqual(ConversationSearch.matches(messages, query: " миграцию ").map(\.id), ["1"])
        XCTAssertEqual(ConversationSearch.matches(messages, query: "db/schema.sql").map(\.id), ["1", "2"])
        XCTAssertTrue(ConversationSearch.matches(messages, query: " \n ").isEmpty)
        XCTAssertTrue(ConversationSearch.matches(messages, query: "unknown").isEmpty)
    }

    func testSnippetIncludesMatchDeepInsideLongUnicodeMessage() {
        let text = String(repeating: "Предыстория 🐧. ", count: 100) + "МИГРАЦИЯ" + String(repeating: " окончание", count: 100)
        let snippet = ConversationSearch.snippet(text, query: "миграция")
        XCTAssertTrue(snippet.contains("МИГРАЦИЯ"))
        XCTAssertTrue(snippet.hasPrefix("…"))
        XCTAssertTrue(snippet.hasSuffix("…"))
        XCTAssertLessThan(snippet.count, 180)
    }

    func testHighlightPreservesTextWithRepeatedMatchesAndUnicode() {
        let text = "🐧 Миграция, миграция."
        let highlighted = ConversationSearch.highlighted(text, query: "миграция")
        XCTAssertEqual(String(highlighted.characters), text)
        XCTAssertEqual(highlighted.runs.filter { $0.backgroundColor != nil }.count, 2)
        XCTAssertEqual(String(ConversationSearch.highlighted(text, query: "").characters), text)
    }
}
