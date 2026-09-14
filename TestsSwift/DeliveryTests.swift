import XCTest
@testable import AgentAttention

final class DeliveryTests: XCTestCase {
    func testMarkReadRemovesQuestionFromQueueWithoutAnsweringAndCanBeUndone() throws {
        try withStore { store in
            let question = session("waiting", token: "unread")
            store.merge([question])
            store.local.drafts[question.token] = ["text": "Later"]
            store.toggleRead(question)
            XCTAssertTrue(store.pending.isEmpty)
            XCTAssertEqual(store.aggregate, "idle")
            XCTAssertEqual(store.visible.first?.status, "waiting")
            XCTAssertEqual(store.visible.first?.canReply, question.canReply)
            XCTAssertEqual(store.local.drafts[question.token]?["text"], "Later")
            XCTAssertTrue(store.local.uncertain?.isEmpty ?? true)
            store.merge([question])
            XCTAssertTrue(store.pending.isEmpty)
            store.toggleRead(question)
            XCTAssertEqual(store.pending.map(\.id), [question.id])
        }
    }

    func testNewQuestionNeedsAttentionAfterPreviousQuestionWasRead() throws {
        try withStore { store in
            let question = session("waiting", token: "unread")
            store.merge([question])
            store.toggleRead(question)
            store.merge([session("waiting", token: "new")])
            XCTAssertEqual(store.pending.count, 1)
            store.toggleRead(store.pending[0])
            store.merge([session("working")])
            store.merge([session("waiting", token: "new")])
            XCTAssertEqual(store.pending.count, 1)
        }
    }

    func testReadQuestionSurvivesRestartAndDoesNotHideOtherSessions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(storageDirectory: dir, notificationsEnabled: false)
        let question = session("waiting", token: "unread")
        var other = question; other.id = "other"
        store.merge([question, other])
        store.toggleRead(question)
        let restored = Store(storageDirectory: dir, notificationsEnabled: false)
        restored.merge([question, other])
        XCTAssertEqual(restored.pending.map(\.id), [other.id])
        restored.merge([other])
        XCTAssertNil(restored.local.readQuestions?[question.id])
    }

    func testMarkReadDoesNotHideUnconfirmedDelivery() throws {
        try withStore { store in
            for status in ["checking", "unconfirmed"] {
                let question = session(status)
                store.local.sessions = [question]
                store.toggleRead(question)
                XCTAssertEqual(store.pending.count, 1)
            }
        }
    }

    func testFailedOrDisabledSourceKeepsSessionsUntilSuccessfulRefresh() throws {
        try withStore { store in
            store.local.sessions = [session("done")]
            store.merge([], completeSources: ["Claude Code"])
            XCTAssertEqual(store.visible.count, 1)
            store.merge([], completeSources: ["herdr"])
            XCTAssertTrue(store.visible.isEmpty)
            XCTAssertNil(store.selected)
        }
    }
    func testRemovingSessionClearsItsSavedQueueState() throws {
        try withStore { store in
            store.local.excluded = ["test"]
            store.local.seen = ["test"]
            store.local.names = ["test": "Old name"]
            store.local.drafts = ["old": ["text": "Draft"]]
            store.local.snoozes = ["old": 100]
            store.merge([])
            XCTAssertTrue(store.local.sessions.isEmpty)
            XCTAssertTrue(store.local.excluded.isEmpty)
            XCTAssertTrue(store.local.seen.isEmpty)
            XCTAssertTrue(store.local.names.isEmpty)
            XCTAssertTrue(store.local.drafts.isEmpty)
            XCTAssertTrue(store.local.snoozes.isEmpty)
            XCTAssertTrue(store.local.uncertain?.isEmpty ?? false)
        }
    }
    func testDeletedSessionDisappearsAndSelectionMovesToRemainingDialogue() throws {
        try withStore { store in
            let removed = session("done")
            var remaining = session("working"); remaining.id = "remaining"
            store.local.sessions = [removed, remaining]
            store.selected = removed.id
            store.merge([remaining])
            XCTAssertEqual(store.visible.map(\.id), [remaining.id])
            XCTAssertEqual(store.selected, remaining.id)
        }
    }
    func testOpeningCompletedDialogueMarksItViewedAcrossPolling() throws {
        try withStore { store in
            let completed = session("done")
            store.merge([completed])
            store.choose(completed)
            XCTAssertEqual(store.current?.status, "viewed")
            XCTAssertTrue(store.local.seen.contains(completed.id))
            store.merge([completed])
            XCTAssertEqual(store.current?.status, "viewed")
            store.merge([session("working")])
            store.merge([completed])
            XCTAssertEqual(store.current?.status, "done", "A new result must remain unread until opened")
        }
    }
    func testAutomaticSelectionDoesNotMarkResultViewed() throws {
        try withStore { store in
            store.merge([session("done")])
            XCTAssertEqual(store.current?.status, "done")
            XCTAssertTrue(store.local.seen.isEmpty)
        }
    }
    func testViewedResultSurvivesRestart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(storageDirectory: dir, notificationsEnabled: false)
        let completed = session("done")
        store.merge([completed])
        store.choose(completed)
        let reopened = Store(storageDirectory: dir, notificationsEnabled: false)
        reopened.merge([completed])
        XCTAssertEqual(reopened.current?.status, "viewed")
        XCTAssertTrue(reopened.local.seen.contains(completed.id))
    }
    func testOpeningWaitingDialogueDoesNotDismissQuestion() throws {
        try withStore { store in
            let waiting = session("waiting", token: "new")
            store.merge([waiting])
            store.choose(waiting)
            XCTAssertEqual(store.current?.status, "waiting")
            XCTAssertTrue(store.current?.canReply ?? false)
            XCTAssertTrue(store.local.seen.isEmpty)
        }
    }
    func testProgressAdvancesQueueButUncertaintyDoesNot() throws {
        for progressed in [false, true] {
            try withStore { store in
                var next = session("waiting", token: "next"); next.id = "next"
                store.selected = "test"
                store.advanceAfterReply = ["test": "old"]
                store.local.deliveryStarted = ["test": Date().timeIntervalSince1970]
                store.merge([session(progressed ? "working" : "waiting"), next])
                XCTAssertEqual(store.selected, progressed ? "next" : "test")
            }
        }
    }
    func testManualNavigationCancelsPendingAutomaticAdvance() throws {
        try withStore { store in
            store.selected = "test"
            store.advanceAfterReply = ["test": "old"]
            store.selected = "another"
            store.selected = "test"
            var next = session("waiting", token: "next"); next.id = "next"
            store.merge([session("working"), next])
            XCTAssertEqual(store.selected, "test")
        }
    }
    func testUnknownDeliveryDoesNotAdvanceAfterLaterProgress() throws {
        try withStore { store in
            store.selected = "test"
            store.advanceAfterReply = ["test": "old"]
            var next = session("waiting", token: "next"); next.id = "next"
            store.merge([session("waiting"), next])
            store.merge([session("working"), next])
            XCTAssertEqual(store.selected, "test")
        }
    }
    func testChoiceAndCommentAreSeparateAndPersistTogether() throws {
        try withStore { store in
            var question = session("waiting", token: "question")
            question.fields = [QuestionField(id: "layout", label: "Layout", options: [FieldOption(label: "Cards")], multi: false)]
            store.setDraft(question, field: "layout", value: "Cards")
            store.setComment(question, field: "layout", value: "Keep dates visible")
            XCTAssertEqual(store.draft(question, field: "layout"), "Cards")
            XCTAssertEqual(store.answers(question)["layout"], "Cards — Keep dates visible")
            store.setDraft(question, field: "layout", value: "")
            XCTAssertEqual(store.answers(question)["layout"], "Keep dates visible")
            store.local.sessions = [question]
            store.merge([question])
            XCTAssertEqual(store.comment(question, field: "layout"), "Keep dates visible")
        }
    }
    func testLegacyCustomAnswerStaysVisibleAsComment() throws {
        try withStore { store in
            var question = session("waiting", token: "question")
            question.fields = [QuestionField(id: "layout", label: "Layout", options: [FieldOption(label: "Cards")], multi: false)]
            store.setDraft(question, field: "layout", value: "Something else")
            store.separateLegacyComments(question)
            XCTAssertEqual(store.comment(question, field: "layout"), "Something else")
            XCTAssertEqual(store.draft(question, field: "layout"), "")
            XCTAssertEqual(store.answers(question)["layout"], "Something else")
        }
    }
    func session(_ status: String, token: String = "old") -> Session {
        Session(id: "test", title: "Test", project: "/tmp/test", agent: "codex", source: "herdr", status: status, question: status == "waiting" ? "Continue?" : "", options: [], token: token, canReply: status == "waiting", kind: "screen", updated: 1, target: [:], detail: "", fields: [])
    }
    func withStore(_ body: (Store) -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var saved = LocalState(); saved.sessions = [session("unconfirmed")]; saved.uncertain = ["test": "old"]
        try JSONEncoder().encode(saved).write(to: dir.appendingPathComponent("state.json"))
        let store = Store(storageDirectory: dir, notificationsEnabled: false)
        store.local.sessions = [session("unconfirmed")]
        body(store)
    }
    func testAgentContinuesAfterReply() throws {
        try withStore { store in
            store.merge([session("working", token: "next")])
            XCTAssertEqual(store.current?.status, "working", "A live working agent must not be stuck in delivery uncertainty")
            XCTAssertTrue(store.pending.isEmpty)
            XCTAssertNil(store.local.uncertain?["test"])
        }
    }
    func testSameQuestionRemainsProtectedFromDuplicateReply() throws {
        try withStore { store in
            store.merge([session("waiting")])
            XCTAssertEqual(store.current?.status, "unconfirmed")
            XCTAssertFalse(store.current?.canReply ?? true)
        }
    }
    func testDisconnectedSessionShowsDisconnected() throws {
        try withStore { store in
            store.merge([session("offline")])
            XCTAssertEqual(store.current?.status, "offline")
            XCTAssertEqual(store.local.uncertain?["test"], "old")
        }
    }
    func testNextQuestionIsAnswerable() throws {
        try withStore { store in
            store.merge([session("waiting", token: "new-question")])
            XCTAssertTrue(store.current?.canReply ?? false)
            XCTAssertNil(store.local.uncertain?["test"])
        }
    }
    func testRecentSendDoesNotImmediatelyShowFailure() throws {
        try withStore { store in
            store.local.deliveryStarted = ["test": Date().timeIntervalSince1970]
            store.merge([session("waiting")])
            XCTAssertEqual(store.current?.status, "checking")
            XCTAssertFalse(store.current?.canReply ?? true)
        }
    }
    func testRestartClearsOldUncertaintyWhenAgentIsWorking() throws {
        try withStore { store in
            store.local.sessions[0].status = "offline"
            store.merge([session("working", token: "next")])
            XCTAssertEqual(store.current?.status, "working")
            XCTAssertNil(store.local.uncertain?["test"])
        }
    }
    func testNextQuestionSkipsWorkingAndPreservesDrafts() throws {
        try withStore { store in
            var first = session("waiting", token: "one"); first.id = "one"
            var second = session("waiting", token: "two"); second.id = "two"
            var working = session("working"); working.id = "working"
            store.local.sessions = [first, working, second]
            store.local.arrival = ["one": 1, "two": 2]
            store.local.drafts = ["one": ["text": "Saved answer"]]
            store.selected = "one"
            store.nextQuestion()
            XCTAssertEqual(store.selected, "two")
            store.nextQuestion()
            XCTAssertEqual(store.selected, "one")
            XCTAssertEqual(store.local.drafts["one"]?["text"], "Saved answer")
        }
    }
    func testPollingDoesNotStealSelectedQuestion() throws {
        try withStore { store in
            var first = session("waiting", token: "one"); first.id = "one"
            var second = session("waiting", token: "two"); second.id = "two"
            store.local.sessions = [first]; store.selected = "one"
            store.merge([first, second])
            XCTAssertEqual(store.selected, "one")
        }
    }
}
