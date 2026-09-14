import XCTest
@testable import AgentAttention

final class FormattedMessageTests: XCTestCase {
    func testTerminalDiffFromApprovalCard() {
        let source = "playwright.feedback-proof.config.ts (+1 -1)\n  6   expect: { timeout: 15_000 },\n  7 - outputDir: \"../../reports/feedback-\n      validation/browser-artifacts\",\n  7 + outputDir: \"../../reports/new\",\n  8   use: { baseURL: \"http://127.0.0.1\" },\n\n  └ /private/tmp/project"
        let blocks = MessageBlock.parse(source)
        XCTAssertTrue(blocks.contains { block in
            if case .code(let value, diff: true) = block {
                return value.contains("7 - outputDir") && value.contains("7 + outputDir")
            }
            return false
        }, "Numbered terminal diff must render as literal highlighted code")
        XCTAssertEqual(MessageBlock.change("  7 - outputDir: old"), -1)
        XCTAssertEqual(MessageBlock.change("  7 + outputDir: new"), 1)
        XCTAssertEqual(MessageBlock.changes(in: "  6   context\n  7 − old\n      continuation\n  7 + new\n      continuation\n  8   context"), [0, -1, -1, 1, 1, 0])
        XCTAssertEqual(MessageBlock.parse("1. First\n2. Second\n- item\n+ item\n42 plain text"), [.prose("1. First\n2. Second\n- item\n+ item\n42 plain text")])
    }

    func testListsAreProseAndCodeRemainsLiteral() {
        XCTAssertEqual(MessageBlock.parse("- item\n+ item\n```swift\n  let x = \"**literal**\"\n-1\n```"), [
            .prose("- item\n+ item"), .code("  let x = \"**literal**\"\n-1", diff: false)
        ])
    }

    func testDiffFencesAndTrailingProse() {
        XCTAssertEqual(MessageBlock.parse("Before\n```diff\n-old\n+new\n context\n```\nAfter"), [
            .prose("Before"), .code("-old\n+new\n context", diff: true), .prose("After")
        ])
        XCTAssertEqual(MessageBlock.change("-old"), -1)
        XCTAssertEqual(MessageBlock.change("+new"), 1)
        for line in [" context", "@@ -1 +1 @@", "--- a/file", "+++ b/file"] {
            XCTAssertEqual(MessageBlock.change(line), 0)
        }
    }

    func testIncompleteAndNestedFencesPreserveCode() {
        XCTAssertEqual(MessageBlock.parse("~~~~patch\n-old\n~~~\n+new"), [
            .code("-old\n~~~\n+new", diff: true)
        ])
        XCTAssertEqual(MessageBlock.parse("```\n\t**raw**\n\n```"), [.code("\t**raw**\n", diff: false)])
    }
}
