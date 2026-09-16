import XCTest
import UserNotifications
@testable import AgentAttention

final class NotificationDeliveryTests: XCTestCase {
    final class Transport: NotificationTransport {
        var access = NotificationAccess(authorization: .notDetermined)
        var authorizationRequests = 0
        var authorizationCompletion: ((Bool, Error?) -> Void)?
        var requests: [UNNotificationRequest] = []
        var error: Error?
        func settings(_ completion: @escaping (NotificationAccess) -> Void) { completion(access) }
        func authorize(_ completion: @escaping (Bool, Error?) -> Void) {
            authorizationRequests += 1; authorizationCompletion = completion
        }
        func add(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
            requests.append(request); completion(error)
        }
    }
    private func request(_ id: String) -> UNNotificationRequest {
        UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: nil)
    }
    private func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }

    func testFirstQuestionWaitsForUserToGrantPermission() {
        let transport = Transport(), delivered = expectation(description: "Delivered after permission")
        let delivery = NotificationDelivery(transport: transport)
        delivery.send(request("question")) { error in XCTAssertNil(error); delivered.fulfill() }
        drain()
        XCTAssertTrue(transport.requests.isEmpty, "First question must not be lost while permission dialog is open")
        XCTAssertEqual(transport.authorizationRequests, 1)
        transport.access = NotificationAccess(authorization: .authorized)
        transport.authorizationCompletion?(true, nil)
        wait(for: [delivered], timeout: 1)
        XCTAssertEqual(transport.requests.map(\.identifier), ["question"])
    }
    func testDeniedPermissionIsAnActionableFailureInsteadOfSilentAcceptance() {
        let transport = Transport(), completed = expectation(description: "Denied reported")
        transport.access = NotificationAccess(authorization: .denied)
        let delivery = NotificationDelivery(transport: transport)
        delivery.send(request("question")) { error in
            XCTAssertNotNil(error, "The app must surface disabled notifications")
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testSeveralEventsSharePermissionPromptAndAreDeliveredOnce() {
        let transport = Transport(), completed = expectation(description: "Both delivered")
        completed.expectedFulfillmentCount = 2
        let delivery = NotificationDelivery(transport: transport)
        delivery.send(request("question")) { _ in completed.fulfill() }
        delivery.send(request("done")) { _ in completed.fulfill() }
        drain()
        XCTAssertEqual(transport.authorizationRequests, 1)
        transport.access = NotificationAccess(authorization: .authorized)
        transport.authorizationCompletion?(true, nil)
        wait(for: [completed], timeout: 1)
        XCTAssertEqual(transport.requests.map(\.identifier), ["question", "done"])
    }
    func testAuthorizedWithNoBannerStyleIsNotReportedAsBannerEnabled() {
        let settings = NotificationAccess(authorization: .authorized, banners: false)
        XCTAssertFalse(settings.canShowBanner)
        XCTAssertEqual(settings.summary, "Только Центр уведомлений")
        XCTAssertTrue(settings.guidance.contains("Баннеры"))
        XCTAssertFalse(NotificationAccess(authorization: .provisional).canShowBanner)
    }
    func testEnableInSystemSettingsAfterDenialAllowsNextEvent() {
        let transport = Transport(), failed = expectation(description: "Denied"), delivered = expectation(description: "Allowed")
        transport.access = NotificationAccess(authorization: .denied)
        let delivery = NotificationDelivery(transport: transport)
        delivery.send(request("old")) { error in XCTAssertNotNil(error); failed.fulfill() }
        wait(for: [failed], timeout: 1)
        transport.access = NotificationAccess(authorization: .authorized)
        delivery.send(request("new")) { error in XCTAssertNil(error); delivered.fulfill() }
        wait(for: [delivered], timeout: 1)
        XCTAssertEqual(transport.requests.map(\.identifier), ["new"])
    }
    func testSystemErrorIsSurfacedWithoutRetry() {
        let transport = Transport(), completed = expectation(description: "Error shown")
        transport.access = NotificationAccess(authorization: .authorized)
        transport.error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Delivery failed"])
        let delivery = NotificationDelivery(transport: transport)
        delivery.send(request("question")) { error in XCTAssertNotNil(error); completed.fulfill() }
        wait(for: [completed], timeout: 1)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertTrue(delivery.lastResult?.contains("Delivery failed") == true)
    }
    func testAllPresentationDisabledIsReportedAndNotSubmitted() {
        let transport = Transport(), completed = expectation(description: "Presentation disabled")
        transport.access = NotificationAccess(authorization: .authorized, alerts: false, banners: false, center: false)
        let delivery = NotificationDelivery(transport: transport)
        delivery.send(request("question")) { error in XCTAssertNotNil(error); completed.fulfill() }
        wait(for: [completed], timeout: 1)
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
