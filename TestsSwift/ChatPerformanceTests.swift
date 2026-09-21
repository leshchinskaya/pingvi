import AppKit
import Combine
import XCTest
@testable import AgentAttention

final class ChatPerformanceTests: XCTestCase {
    func testHiddenOrOccludedSurfaceDoesNotRefreshChat() {
        XCTAssertFalse(ChatRefreshPolicy.allowsMainWindow(appIsActive: false, isVisible: true, occlusionState: .visible))
        XCTAssertFalse(ChatRefreshPolicy.allowsMainWindow(appIsActive: true, isVisible: false, occlusionState: .visible))
        XCTAssertFalse(ChatRefreshPolicy.allowsMainWindow(appIsActive: true, isVisible: true, occlusionState: []))
        XCTAssertTrue(ChatRefreshPolicy.allowsMainWindow(appIsActive: true, isVisible: true, occlusionState: .visible))
    }

    func testRepeatedIdenticalHistoryDoesNotInvalidateChatView() {
        let model = ChatModel()
        let history = ChatHistory(
            messages: [ChatMessage(id: "one", role: "assistant", text: "Done", state: "received")],
            partial: false,
            context: "",
            canSend: true,
            busy: false,
            reason: "",
            token: "screen",
            pending: false
        )
        model.updateHistory(history)

        var updates = 0
        let observation = model.objectWillChange.sink { updates += 1 }
        model.updateHistory(history)
        model.updateError(nil)
        XCTAssertEqual(updates, 0, "An unchanged three-second refresh must not rebuild the chat view")

        var changed = history
        changed.messages.append(ChatMessage(id: "two", role: "assistant", text: "New", state: "received"))
        model.updateHistory(changed)
        XCTAssertEqual(updates, 1, "A new message must still update the visible chat")
        withExtendedLifetime(observation) {}
    }
}
