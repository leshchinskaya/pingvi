import PingviLink
import XCTest
@testable import Pingvi

@MainActor
final class MobileRouterTests: XCTestCase {
    private let session = PingviSessionSummary(
        id: "s1", title: "Session", project: "Project", projectPath: "/Project",
        agent: "codex", source: "herdr", status: "done", preview: "", updatedAt: Date(timeIntervalSince1970: 0)
    )

    func testPushAppendsToTabStackAndSelectsTab() {
        let router = MobileRouter()
        router.tab = .settings

        router.push(.conversation(session), in: .dialogs)

        XCTAssertEqual(router.tab, .dialogs)
        XCTAssertEqual(router.dialogsPath, [.conversation(session)])
        XCTAssertTrue(router.queuePath.isEmpty)
    }

    func testOpenReplacesExistingStack() {
        let router = MobileRouter()
        router.push(.conversation(session), in: .queue)
        router.push(.conversation(session), in: .queue)

        router.open(.conversation(session), in: .queue)

        XCTAssertEqual(router.queuePath.count, 1)
    }

    func testResetReturnsToEmptyQueue() {
        let router = MobileRouter()
        router.push(.conversation(session), in: .dialogs)

        router.reset()

        XCTAssertEqual(router.tab, .queue)
        XCTAssertTrue(router.dialogsPath.isEmpty)
    }
}
