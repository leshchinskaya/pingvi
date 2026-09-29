import PingviLink
import XCTest
@testable import Pingvi

@MainActor
final class MobileUndoQueueTests: XCTestCase {
    private let reply = PingviReply(sessionID: "s1", questionToken: "t1", answer: "yes")

    func testScheduledReplyCommitsAfterGracePeriod() async throws {
        let queue = MobileUndoQueue(delay: .milliseconds(50))
        var committed: [PingviReply] = []

        queue.schedule(reply, label: "Да") { committed.append($0) }
        XCTAssertNotNil(queue.pending["s1"])
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(committed, [reply])
        XCTAssertNil(queue.pending["s1"])
    }

    func testCancelledReplyNeverCommits() async throws {
        let queue = MobileUndoQueue(delay: .milliseconds(50))
        var committed: [PingviReply] = []

        queue.schedule(reply, label: "Да") { committed.append($0) }
        queue.cancel(sessionID: "s1")
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(committed.isEmpty)
        XCTAssertNil(queue.pending["s1"])
    }

    func testNewTapReplacesPendingReplyForSameSession() async throws {
        let queue = MobileUndoQueue(delay: .milliseconds(50))
        let other = PingviReply(sessionID: "s1", questionToken: "t1", answer: "no")
        var committed: [PingviReply] = []

        queue.schedule(reply, label: "Да") { committed.append($0) }
        queue.schedule(other, label: "Нет") { committed.append($0) }
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(committed, [other])
    }

    func testDeadlineMatchesDelay() {
        let queue = MobileUndoQueue(delay: .seconds(3))
        let now = Date(timeIntervalSince1970: 1_000)

        queue.schedule(reply, label: "Да", now: now) { _ in }

        XCTAssertEqual(queue.pending["s1"]?.deadline, now.addingTimeInterval(3))
        queue.cancelAll()
    }
}
