import PingviLink
import XCTest
@testable import Pingvi

final class MobileReplyTests: XCTestCase {
    func testShortAnswerUsesTextFieldForCodexQuestion() {
        let question = PingviQuestion(
            id: "question", token: "token", title: "Question", project: "Project",
            agent: "codex", source: "herdr", question: "Как назвать экран?", context: "",
            options: [],
            fields: [PingviQuestionField(id: "text", label: "Короткий ответ", options: [], allowsMultiple: false)],
            state: .waiting, canReply: true, arrivedAt: Date()
        )

        let raw = PingviReply(sessionID: question.id, questionToken: question.token, answer: "  Главный экран  ")
        let reply = MobileReplyBuilder.normalized(raw, for: question)

        XCTAssertEqual(reply.answer, "")
        XCTAssertEqual(reply.fieldAnswers, ["text": "Главный экран"])
    }

    func testApprovalChoiceKeepsOptionIdentifier() {
        let question = PingviQuestion(
            id: "question", token: "token", title: "Question", project: "Project",
            agent: "codex", source: "herdr", question: "Разрешить?", context: "",
            options: [PingviOption(id: "2", label: "Да, всегда")], fields: [],
            state: .waiting, canReply: true, arrivedAt: Date()
        )

        let raw = PingviReply(sessionID: question.id, questionToken: question.token, answer: question.options[0].replyValue)
        let reply = MobileReplyBuilder.normalized(raw, for: question)

        XCTAssertEqual(reply.answer, "2")
        XCTAssertTrue(reply.fieldAnswers.isEmpty)
    }
}
