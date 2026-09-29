import XCTest

final class MobileConversationScrollTests: XCTestCase {
    func testUnreadDialogOffersMarkAsReadAction() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--documentation-preview",
            "--documentation-screen", "dialogs"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Отметить «Уведомления на устройствах» прочитанным"].waitForExistence(timeout: 3))
    }

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

    func testQueueStartsWithContentInsteadOfRepeatedTitles() {
        let app = XCUIApplication()
        app.launchArguments = ["--documentation-preview", "--documentation-screen", "queue"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Ждут ответа"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Очередь агента"].exists)
        XCTAssertFalse(app.navigationBars["Pingvi"].exists)
        XCTAssertFalse(app.staticTexts["Нет связи с Mac"].exists, "При активном соединении баннер не показывается")
    }

    func testQuestionOpensFromQueueThroughRouter() {
        let app = XCUIApplication()
        app.launchArguments = ["--documentation-preview", "--documentation-screen", "queue"]
        app.launch()

        let card = app.staticTexts["Разрешить запуск тестов интерфейса на этом Mac?"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.tap()
        XCTAssertTrue(app.staticTexts["Быстрый ответ"].waitForExistence(timeout: 3) || app.buttons["Да"].waitForExistence(timeout: 1))
    }

    func testQuickReplyCanBeUndoneFromQueueCard() {
        let app = XCUIApplication()
        app.launchArguments = ["--documentation-preview", "--documentation-screen", "queue"]
        app.launch()

        let yes = app.buttons["Да"]
        XCTAssertTrue(yes.waitForExistence(timeout: 3))
        yes.tap()

        let undo = app.buttons["Отменить"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2), "После тапа по варианту показывается окно отмены")
        undo.tap()
        XCTAssertTrue(app.buttons["Да"].waitForExistence(timeout: 2), "После отмены варианты возвращаются")
    }

    func testQuestionOpensAsSheetWithCloseButton() {
        let app = XCUIApplication()
        app.launchArguments = ["--documentation-preview", "--documentation-screen", "queue", "--ui-test-question-sheet"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Быстрый ответ"].waitForExistence(timeout: 3))
        app.buttons["Закрыть"].tap()
        XCTAssertTrue(app.staticTexts["Ждут ответа"].waitForExistence(timeout: 3))
    }

    func testAgentMarkdownRendersCodeBlockWithCopyAction() {
        let app = XCUIApplication()
        app.launchArguments = ["--documentation-preview", "--documentation-screen", "conversation"]
        app.launch()

        XCTAssertTrue(app.buttons["Скопировать код"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["```sh"].exists, "Разметка не должна показываться сырой")
        XCTAssertFalse(
            app.staticTexts["Сообщение будет передано в исходную сессию на Mac."].exists,
            "Подпись под полем ввода показывается только при проблеме"
        )
    }
}
