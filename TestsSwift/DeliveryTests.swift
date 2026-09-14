import XCTest
@testable import AgentAttention

final class DeliveryTests: XCTestCase {
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
