import PingviLink
import XCTest
@testable import Pingvi

final class MobileDialogsTests: XCTestCase {
    private func session(_ id: String, _ status: String) -> PingviSessionSummary {
        PingviSessionSummary(
            id: id, title: id, project: "P", projectPath: "/P", agent: "codex",
            source: "herdr", status: status, preview: "", updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testFiltersMatchStatuses() {
        XCTAssertTrue(DialogsFilter.waiting.includes(session("a", "unconfirmed")))
        XCTAssertFalse(DialogsFilter.waiting.includes(session("b", "working")))
        XCTAssertTrue(DialogsFilter.working.includes(session("c", "working")))
        XCTAssertFalse(DialogsFilter.working.includes(session("d", "waiting")))
        XCTAssertTrue(DialogsFilter.done.includes(session("e", "done")))
        XCTAssertFalse(DialogsFilter.done.includes(session("f", "viewed")))
        XCTAssertTrue(DialogsFilter.all.includes(session("f", "future")))
    }

    func testGroupsKeepOrderAndSkipEmptySections() {
        let groups = DialogsGrouping.groups([
            session("done", "done"), session("run", "working"), session("ask", "waiting"), session("old", "viewed")
        ])

        XCTAssertEqual(groups.map(\.id), ["waiting", "working", "recent"])
        XCTAssertEqual(groups.last?.sessions.map(\.id), ["done", "old"])
        XCTAssertEqual(DialogsGrouping.groups([session("x", "done")]).map(\.id), ["recent"])
    }

    @MainActor
    func testPairingCodeAcceptsMissingScheme() {
        XCTAssertEqual(MobileAppModel.normalizedPairingCode(" pair?v=1 "), "pingvi://pair?v=1")
        XCTAssertEqual(MobileAppModel.normalizedPairingCode("pingvi://pair?v=1"), "pingvi://pair?v=1")
        XCTAssertEqual(MobileAppModel.normalizedPairingCode("PINGVI://pair"), "PINGVI://pair")
        XCTAssertEqual(MobileAppModel.normalizedPairingCode("//pair"), "pingvi://pair")
        XCTAssertEqual(MobileAppModel.normalizedPairingCode("  "), "")
    }
}
