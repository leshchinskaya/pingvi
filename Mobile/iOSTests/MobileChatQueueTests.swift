import XCTest
@testable import Pingvi

final class MobileChatQueueTests: XCTestCase {
    func testLaterMessagesAppendInsteadOfReplacing() {
        let first = MobileChatQueue.enqueue("  Первое  ", into: nil, now: Date(timeIntervalSince1970: 1))
        let both = MobileChatQueue.enqueue("Второе", into: first, now: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(first.text, "Первое")
        XCTAssertEqual(both.text, "Первое\n\nВторое")
        XCTAssertEqual(both.queuedAt, Date(timeIntervalSince1970: 1), "Время очереди — по первому сообщению")
    }

    func testMessageWaitsBehindQueueAndWhileSessionIsBusy() {
        XCTAssertTrue(MobileChatQueue.sendsImmediately(connected: true, canSend: true, sending: false, hasQueued: false))
        XCTAssertFalse(MobileChatQueue.sendsImmediately(connected: true, canSend: false, sending: false, hasQueued: false))
        XCTAssertFalse(MobileChatQueue.sendsImmediately(connected: false, canSend: true, sending: false, hasQueued: false))
        XCTAssertFalse(MobileChatQueue.sendsImmediately(connected: true, canSend: true, sending: true, hasQueued: false))
        XCTAssertFalse(MobileChatQueue.sendsImmediately(connected: true, canSend: true, sending: false, hasQueued: true),
                       "Новое сообщение не обгоняет уже стоящее в очереди")
    }

    func testDeliveryNeedsReadySessionAndFreeChannel() {
        XCTAssertTrue(MobileChatQueue.readyToDeliver(connected: true, canSend: true, sending: false))
        XCTAssertFalse(MobileChatQueue.readyToDeliver(connected: true, canSend: false, sending: false))
        XCTAssertFalse(MobileChatQueue.readyToDeliver(connected: true, canSend: true, sending: true))
    }
}
