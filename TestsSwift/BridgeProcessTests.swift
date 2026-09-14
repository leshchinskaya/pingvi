import XCTest
@testable import AgentAttention

final class BridgeProcessTests: XCTestCase {
    func testStuckHelperTimesOutAndNextCallWorks() throws {
        let start = Date()
        XCTAssertThrowsError(try BridgeProcess.run(executable: "/bin/sh", arguments: ["-c", "exec sleep 30"], input: Data(), timeout: 0.1)) {
            XCTAssertEqual(($0 as NSError).code, 408)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        let data = try BridgeProcess.run(executable: "/bin/cat", arguments: [], input: Data("ok".utf8), timeout: 2)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
    }
    func testLargeStderrDoesNotBlockOutput() throws {
        let data = try BridgeProcess.run(executable: "/bin/sh", arguments: ["-c", "dd if=/dev/zero bs=1024 count=256 >&2; echo ok"], input: Data(), timeout: 3)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok\n")
    }
}
