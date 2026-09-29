import XCTest
@testable import AgentAttention

final class MobileCompletionSummaryTests: XCTestCase {
    func testPreviewFlattensMarkdownIntoOneParagraph() {
        let answer = """
        ## Готово

        - Добавил **бейджи** на вкладки
        ```swift
        let x = 1
        ```
        Проверил `xcodebuild`.
        """

        XCTAssertEqual(
            MobileCompletionSummary.preview(from: answer),
            "Готово Добавил бейджи на вкладки Проверил xcodebuild."
        )
    }

    func testPreviewFallsBackAndTruncates() {
        XCTAssertEqual(MobileCompletionSummary.preview(from: nil), MobileCompletionSummary.fallback)
        XCTAssertEqual(MobileCompletionSummary.preview(from: "  \n "), MobileCompletionSummary.fallback)
        let long = String(repeating: "а", count: 400)
        let preview = MobileCompletionSummary.preview(from: long, limit: 10)
        XCTAssertEqual(preview, String(repeating: "а", count: 10) + "…")
    }
}
