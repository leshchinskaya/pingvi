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

    func testMultiSelectAnswerUsesMacSeparatorAndOptionOrder() {
        let field = PingviQuestionField(
            id: "layers", label: "Слои",
            options: [PingviOption(id: "UI", label: "UI"), PingviOption(id: "API", label: "API"), PingviOption(id: "DB", label: "DB")],
            allowsMultiple: true
        )

        XCTAssertEqual(MobileReplyBuilder.joined(["DB", "UI"], in: field), "UI, DB")
        XCTAssertEqual(MobileReplyBuilder.joined([], in: field), "")
    }

    func testSyncTextDescribesFreshAndMissingSnapshots() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertNil(MobileSyncText.updated(nil, now: now))
        XCTAssertEqual(MobileSyncText.updated(now.addingTimeInterval(-20), now: now), "обновлено только что")
        XCTAssertNotNil(MobileSyncText.updated(now.addingTimeInterval(-600), now: now))
    }

    func testQuickReplyOnlyForPlainChoicesUpToThree() {
        func question(options: Int, fields: [PingviQuestionField] = [], canReply: Bool = true, state: PingviQuestionState = .waiting) -> PingviQuestion {
            PingviQuestion(
                id: "q", token: "t", title: "Q", project: "P", agent: "codex", source: "herdr",
                question: "?", context: "",
                options: (0..<options).map { PingviOption(id: "\($0)", label: "Вариант \($0)") },
                fields: fields, state: state, canReply: canReply, arrivedAt: Date()
            )
        }
        let field = PingviQuestionField(id: "f", label: "F", options: [], allowsMultiple: false)

        XCTAssertTrue(MobileReplyBuilder.supportsQuickReply(question(options: 3)))
        XCTAssertFalse(MobileReplyBuilder.supportsQuickReply(question(options: 0)))
        XCTAssertFalse(MobileReplyBuilder.supportsQuickReply(question(options: 4)))
        XCTAssertFalse(MobileReplyBuilder.supportsQuickReply(question(options: 2, fields: [field])))
        XCTAssertFalse(MobileReplyBuilder.supportsQuickReply(question(options: 2, canReply: false)))
        XCTAssertFalse(MobileReplyBuilder.supportsQuickReply(question(options: 2, state: .checking)))
    }
}
