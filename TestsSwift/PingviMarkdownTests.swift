import XCTest
@testable import PingviLink

final class PingviMarkdownTests: XCTestCase {
    func testSplitsTypicalAgentAnswerIntoBlocks() {
        let source = """
        ## Итог

        Сделал две вещи:
        - добавил **бейджи**
          на вкладки
        2. обновил `README`

        ```swift
        let x = 1

        print(x)
        ```
        > Нужна проверка на устройстве
        ---
        """

        XCTAssertEqual(PingviMarkdown.blocks(source), [
            .heading(level: 2, text: "Итог"),
            .paragraph("Сделал две вещи:"),
            .listItem(marker: "•", text: "добавил **бейджи**\nна вкладки", indent: 0),
            .listItem(marker: "2.", text: "обновил `README`", indent: 0),
            .code(language: "swift", text: "let x = 1\n\nprint(x)"),
            .quote("Нужна проверка на устройстве"),
            .rule
        ])
    }

    func testKeepsSingleLineBreaksInsideParagraph() {
        XCTAssertEqual(PingviMarkdown.blocks("строка 1\nстрока 2"), [.paragraph("строка 1\nстрока 2")])
    }

    func testUnterminatedFenceStillRendersAsCode() {
        XCTAssertEqual(PingviMarkdown.blocks("```\nlet a = 1"), [.code(language: "", text: "let a = 1")])
    }

    func testTablesAndTaskListsAndNestedItems() {
        let source = """
        | A | B |
        |---|---|
        | 1 | 2 |
        - [x] готово
            - вложенный
        """
        XCTAssertEqual(PingviMarkdown.blocks(source), [
            .code(language: "", text: "| A | B |\n|---|---|\n| 1 | 2 |"),
            .listItem(marker: "☑", text: "готово", indent: 0),
            .listItem(marker: "•", text: "вложенный", indent: 2)
        ])
    }

    func testHashWithoutSpaceIsNotHeading() {
        XCTAssertEqual(PingviMarkdown.blocks("#тег"), [.paragraph("#тег")])
    }
}
