import XCTest

final class MobileConversationScrollTests: XCTestCase {
    func testOpeningLongConversationShowsLatestMessageWithoutUserScroll() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--documentation-preview",
            "--documentation-screen", "conversation",
            "--ui-test-long-conversation",
            "--ui-test-delayed-conversation"
        ]
        app.launch()

        let latestMessage = app.staticTexts["Последнее сообщение диалога"]
        XCTAssertTrue(
            latestMessage.waitForExistence(timeout: 3) && latestMessage.isHittable,
            "Открытый диалог должен сразу показывать последнее сообщение без ручной прокрутки"
        )
    }
}
