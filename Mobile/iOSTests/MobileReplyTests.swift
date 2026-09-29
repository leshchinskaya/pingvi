import PingviLink
import XCTest
@testable import Pingvi

final class MobileReplyTests: XCTestCase {
    func testViewedConversationUpdatesSessionAndRemovesCompletion() {
        let session = PingviSessionSummary(
            id: "done", title: "Result", project: "Project", projectPath: "/Project",
            agent: "codex", source: "herdr", status: "done", preview: "Unread", updatedAt: Date()
        )
        let snapshot = PingviSnapshot(
            revision: 7,
            questions: [],
            completions: [PingviCompletion(id: session.id, title: session.title, agent: session.agent, source: session.source, summary: session.preview, completedAt: Date())],
            sessions: [session]
        )
        let conversation = PingviConversation(
            sessionID: session.id, title: session.title, project: session.project, agent: session.agent,
            source: session.source, status: "viewed", messages: [], partial: false, context: "",
            canSend: true, busy: false, reason: "", token: "token", pending: false
        )

        let updated = MobileSnapshotUpdater.recording(conversation, in: snapshot)

        XCTAssertEqual(updated.sessions.first?.status, "viewed")
        XCTAssertEqual(updated.sessions.first?.preview, "Результат просмотрен")
        XCTAssertTrue(updated.completions.isEmpty)
        XCTAssertEqual(updated.revision, snapshot.revision)
    }

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
