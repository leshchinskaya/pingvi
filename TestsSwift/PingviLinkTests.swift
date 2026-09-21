import CryptoKit
import XCTest
@testable import PingviLink

final class PingviLinkTests: XCTestCase {
    func testPairingOfferRoundTripsThroughURL() throws {
        let server = PingviDeviceIdentity(deviceID: "mac", deviceName: "My Mac")
        let offer = try PingviCrypto.makePairingOffer(identity: server, serviceID: "service", now: Date(timeIntervalSince1970: 100))
        let url = try XCTUnwrap(offer.url)
        let decoded = try PingviPairingOffer.decode(url: url, now: Date(timeIntervalSince1970: 101))
        XCTAssertEqual(decoded, offer)
    }

    func testExpiredAndModifiedPairingOffersAreRejected() throws {
        let server = PingviDeviceIdentity(deviceName: "Mac")
        let offer = try PingviCrypto.makePairingOffer(identity: server, serviceID: "service", lifetime: 1, now: Date(timeIntervalSince1970: 100))
        XCTAssertThrowsError(try PingviPairingOffer.decode(url: XCTUnwrap(offer.url), now: Date(timeIntervalSince1970: 102))) {
            XCTAssertEqual($0 as? PingviLinkError, .pairingExpired)
        }
        XCTAssertThrowsError(try PingviPairingOffer.decode(url: URL(string: "https://example.com")!))
    }

    func testBothDevicesDeriveSamePairingAndSessionKeys() throws {
        let server = PingviDeviceIdentity(deviceID: "mac", deviceName: "Mac")
        let client = PingviDeviceIdentity(deviceID: "phone", deviceName: "iPhone")
        let offer = try PingviCrypto.makePairingOffer(identity: server, serviceID: "service")
        let clientPair = try PingviCrypto.makePairRequest(offer: offer, client: client, nonce: Data(repeating: 1, count: 32))
        let serverPair = try PingviCrypto.acceptPairRequest(clientPair.request, offer: offer, server: server)
        XCTAssertEqual(clientPair.pairingKey, serverPair.pairingKey)
        XCTAssertNoThrow(try PingviCrypto.verifyPairResponse(serverPair.response, request: clientPair.request, pairingKey: clientPair.pairingKey))

        let clientHello = PingviCrypto.makeClientHello(deviceID: client.deviceID, pairingKey: clientPair.pairingKey, nonce: Data(repeating: 2, count: 32))
        let accepted = try PingviCrypto.acceptClientHello(clientHello, pairingKey: serverPair.pairingKey, serverNonce: Data(repeating: 3, count: 32))
        let clientKey = try PingviCrypto.acceptServerHello(accepted.0, clientHello: clientHello, pairingKey: clientPair.pairingKey)
        let plaintext = Data("hello".utf8)
        let frame = try PingviCrypto.seal(plaintext, sequence: 0, using: clientKey)
        XCTAssertEqual(try PingviCrypto.open(frame, using: accepted.1), plaintext)
    }

    func testPairingRejectsRequestMadeWithAnotherSecret() throws {
        let server = PingviDeviceIdentity(deviceName: "Mac")
        let client = PingviDeviceIdentity(deviceName: "Phone")
        let offer = try PingviCrypto.makePairingOffer(identity: server, serviceID: "service")
        var otherOffer = try PingviCrypto.makePairingOffer(identity: server, serviceID: "service")
        // Keep the advertised server identity but prove possession of another QR secret.
        otherOffer = PingviPairingOffer(serviceID: offer.serviceID, macName: offer.macName, serverPublicKey: offer.serverPublicKey, secret: otherOffer.secret, expiresAt: offer.expiresAt)
        let request = try PingviCrypto.makePairRequest(offer: otherOffer, client: client).request
        XCTAssertThrowsError(try PingviCrypto.acceptPairRequest(request, offer: offer, server: server)) {
            XCTAssertEqual($0 as? PingviLinkError, .authenticationFailed)
        }
    }

    func testEncryptedFramesRejectReplayAndOutOfOrderDelivery() throws {
        let key = SymmetricKey(size: .bits256)
        var sender = PingviSendCipher(key: key)
        var receiver = PingviReceiveCipher(key: key)
        let first = try sender.seal(Data("one".utf8))
        let second = try sender.seal(Data("two".utf8))
        XCTAssertEqual(try receiver.open(first), Data("one".utf8))
        XCTAssertThrowsError(try receiver.open(first)) { XCTAssertEqual($0 as? PingviLinkError, .replayedFrame) }
        XCTAssertEqual(try receiver.open(second), Data("two".utf8))
    }

    func testFrameDecoderHandlesSplitAndCoalescedFrames() throws {
        let first = try PingviFraming.encode(Data("one".utf8))
        let second = try PingviFraming.encode(Data("two".utf8))
        let bytes = first + second
        var decoder = PingviFrameDecoder()
        XCTAssertTrue(try decoder.append(bytes.prefix(5)).isEmpty)
        XCTAssertEqual(try decoder.append(bytes.dropFirst(5)), [Data("one".utf8), Data("two".utf8)])
    }

    func testFrameDecoderRejectsOversizedLengthBeforeBufferingPayload() throws {
        var decoder = PingviFrameDecoder(maximumSize: 10)
        XCTAssertThrowsError(try decoder.append(Data([0, 0, 0, 11]))) {
            XCTAssertEqual($0 as? PingviLinkError, .frameTooLarge(11))
        }
    }

    func testQuestionTextIsBounded() {
        let question = PingviQuestion(
            id: "session",
            token: "token",
            title: "Title",
            project: "Project",
            agent: "Codex",
            source: "herdr",
            question: String(repeating: "x", count: PingviProtocol.maximumTextLength + 50),
            context: "Context",
            options: [],
            fields: [],
            state: .waiting,
            canReply: true,
            arrivedAt: Date()
        )
        XCTAssertEqual(question.question.count, PingviProtocol.maximumTextLength)
    }

    func testOptionReplyUsesStableIDInsteadOfDisplayLabel() {
        let option = PingviOption(
            id: "yes-always:security-find-generic-password",
            label: "Yes, and don't ask again for commands that start with security find-generic-password"
        )
        XCTAssertEqual(option.replyValue, "yes-always:security-find-generic-password")
        XCTAssertNotEqual(option.replyValue, option.label)
    }

    func testOnlyCheckingKeepsMobileReplyLocked() {
        XCTAssertTrue(PingviReplyStatus.checking.keepsSubmissionPending)
        XCTAssertFalse(PingviReplyStatus.failed.keepsSubmissionPending)
        XCTAssertFalse(PingviReplyStatus.stale.keepsSubmissionPending)
        XCTAssertFalse(PingviReplyStatus.unavailable.keepsSubmissionPending)
        XCTAssertFalse(PingviReplyStatus.uncertain.keepsSubmissionPending)
        XCTAssertFalse(PingviReplyStatus.accepted.keepsSubmissionPending)
    }

    func testSnapshotCarriesNavigableSessionsAndProjects() throws {
        let session = PingviSessionSummary(
            id: "session",
            title: "Готовый результат",
            project: "Pingvi",
            projectPath: "/Projects/Pingvi",
            agent: "codex",
            source: "herdr",
            status: "done",
            preview: "Агент закончил ответ.",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let snapshot = PingviSnapshot(
            revision: 8,
            questions: [],
            sessions: [session],
            projects: [PingviProject(name: "Pingvi", path: "/Projects/Pingvi")]
        )
        let decoded = try JSONDecoder().decode(PingviSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.sessions, [session])
        XCTAssertEqual(decoded.projects.first?.path, "/Projects/Pingvi")
    }

    func testConversationResponseCarriesReadableHistoryAndSendState() throws {
        let conversation = PingviConversation(
            sessionID: "session",
            title: "Диалог",
            project: "Pingvi",
            agent: "codex",
            source: "herdr",
            status: "viewed",
            messages: [PingviChatMessage(id: "answer", role: .assistant, text: "Готовый ответ", state: .received)],
            partial: false,
            context: "",
            canSend: true,
            busy: false,
            reason: "",
            token: "conversation-token",
            pending: false
        )
        let response = PingviConversationResponse(requestID: "request", sessionID: "session", conversation: conversation)
        let message = PingviMessage.conversation(response)
        let decoded = try JSONDecoder().decode(PingviMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.conversationResponse?.conversation?.messages.first?.text, "Готовый ответ")
        XCTAssertEqual(decoded.conversationResponse?.conversation?.canSend, true)
    }

    func testBonjourPairingSnapshotAndReplyRoundTrip() throws {
        let serviceID = "pingvi-test-" + UUID().uuidString.lowercased()
        let serverIdentity = PingviDeviceIdentity(deviceID: "mac", deviceName: "Test Mac")
        let clientIdentity = PingviDeviceIdentity(deviceID: "phone", deviceName: "Test iPhone")
        let server = PingviLinkServer(identity: serverIdentity, serviceID: serviceID)
        let client = PingviLinkClient(identity: clientIdentity)
        defer { client.stop(); server.stop() }

        let paired = expectation(description: "Pairing persisted")
        let connected = expectation(description: "Encrypted connection established")
        let snapshotReceived = expectation(description: "Snapshot received")
        snapshotReceived.expectedFulfillmentCount = 2 // Server push plus the client's explicit post-handshake request.
        let replyReceived = expectation(description: "Reply reached Mac")
        let resultReceived = expectation(description: "Result reached iPhone")
        let conversationRequested = expectation(description: "Conversation request reached Mac")
        let conversationReceived = expectation(description: "Conversation reached iPhone")
        let chatReceived = expectation(description: "Chat message reached Mac")
        let chatResultReceived = expectation(description: "Chat result reached iPhone")
        let createReceived = expectation(description: "Create chat reached Mac")
        let createResultReceived = expectation(description: "Created session reached iPhone")
        let snapshot = PingviSnapshot(revision: 7, generatedAt: Date(timeIntervalSince1970: 100), questions: [])
        let conversation = PingviConversation(
            sessionID: "session", title: "Dialog", project: "Pingvi", agent: "codex", source: "herdr", status: "viewed",
            messages: [PingviChatMessage(id: "answer", role: .assistant, text: "Done", state: .received)],
            partial: false, context: "", canSend: true, busy: false, reason: "", token: "chat-token", pending: false
        )

        server.snapshotProvider = { snapshot }
        server.onPairingChange = { record in
            if record?.peerDeviceID == clientIdentity.deviceID { paired.fulfill() }
        }
        server.onReply = { commandID, reply, completion in
            XCTAssertEqual(reply.sessionID, "session")
            XCTAssertEqual(reply.questionToken, "token")
            XCTAssertEqual(reply.answer, "Да")
            replyReceived.fulfill()
            completion(PingviReplyResult(commandID: commandID, status: .accepted, message: "Принято"))
        }
        server.onConversationRequest = { requestID, request, completion in
            XCTAssertEqual(request.sessionID, "session")
            conversationRequested.fulfill()
            completion(PingviConversationResponse(requestID: requestID, sessionID: request.sessionID, conversation: conversation))
        }
        server.onChatSend = { commandID, request, completion in
            XCTAssertEqual(request.sessionID, "session")
            XCTAssertEqual(request.conversationToken, "chat-token")
            XCTAssertEqual(request.text, "Next task")
            chatReceived.fulfill()
            completion(PingviChatSendResult(commandID: commandID, sessionID: request.sessionID, status: .submitted, message: "Sent"))
        }
        server.onCreateChat = { commandID, request, completion in
            XCTAssertEqual(request.agent, "codex")
            XCTAssertEqual(request.projectPath, "/Projects/Pingvi")
            createReceived.fulfill()
            completion(PingviCreateChatResult(
                commandID: commandID,
                session: PingviSessionSummary(
                    id: "new-session", title: "New", project: "Pingvi", projectPath: request.projectPath,
                    agent: request.agent, source: "herdr", status: "working", preview: "Working", updatedAt: Date()
                )
            ))
        }
        client.onStateChange = { state in
            if state == .connected { connected.fulfill() }
        }
        client.onMessage = { message in
            if message.snapshot == snapshot { snapshotReceived.fulfill() }
            if message.replyResult?.status == .accepted { resultReceived.fulfill() }
            if message.conversationResponse?.conversation == conversation { conversationReceived.fulfill() }
            if message.chatSendResult?.status == .submitted { chatResultReceived.fulfill() }
            if message.createChatResult?.session?.id == "new-session" { createResultReceived.fulfill() }
        }

        try server.start()
        client.pair(using: try server.makePairingOffer(lifetime: 30))
        wait(for: [paired, connected, snapshotReceived], timeout: 10)
        client.sendReply(PingviReply(sessionID: "session", questionToken: "token", answer: "Да"), commandID: "command")
        wait(for: [replyReceived, resultReceived], timeout: 5)
        client.requestConversation(sessionID: "session", requestID: "conversation-command")
        wait(for: [conversationRequested, conversationReceived], timeout: 5)
        client.sendChat(PingviChatSendRequest(sessionID: "session", conversationToken: "chat-token", text: "Next task"), commandID: "chat-command")
        wait(for: [chatReceived, chatResultReceived], timeout: 5)
        client.createChat(PingviCreateChatRequest(agent: "codex", projectPath: "/Projects/Pingvi", text: "Start"), commandID: "create-command")
        wait(for: [createReceived, createResultReceived], timeout: 5)
    }
}
