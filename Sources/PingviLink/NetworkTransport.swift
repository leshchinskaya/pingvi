import CryptoKit
import Foundation
import Network

public enum PingviConnectionState: Equatable, Sendable {
    case stopped
    case searching
    case connecting
    case connected
    case disconnected(String)

    public var description: String {
        switch self {
        case .stopped: return "Остановлено"
        case .searching: return "Ищем Mac…"
        case .connecting: return "Подключаемся…"
        case .connected: return "На связи"
        case .disconnected(let reason): return reason
        }
    }
}

private enum PingviHandshakeKind: String, Codable {
    case pairRequest
    case pairResponse
    case clientHello
    case serverHello
    case failure
}

private struct PingviHandshake: Codable {
    var kind: PingviHandshakeKind
    var pairRequest: PingviPairRequest?
    var pairResponse: PingviPairResponse?
    var clientHello: PingviClientHello?
    var serverHello: PingviServerHello?
    var error: String?
}

private final class PingviWirePeer: @unchecked Sendable {
    let connection: NWConnection
    var decoder = PingviFrameDecoder()
    var receiveCipher: PingviReceiveCipher?
    var sendCipher: PingviSendCipher?
    var authenticated = false
    var authenticationTimeout: DispatchWorkItem?

    init(connection: NWConnection) {
        self.connection = connection
    }
}

public final class PingviLinkServer: @unchecked Sendable {
    public typealias ReplyHandler = @Sendable (String, PingviReply, @escaping @Sendable (PingviReplyResult) -> Void) -> Void
    public typealias ConversationHandler = @Sendable (String, PingviConversationRequest, @escaping @Sendable (PingviConversationResponse) -> Void) -> Void
    public typealias ChatSendHandler = @Sendable (String, PingviChatSendRequest, @escaping @Sendable (PingviChatSendResult) -> Void) -> Void
    public typealias CreateChatHandler = @Sendable (String, PingviCreateChatRequest, @escaping @Sendable (PingviCreateChatResult) -> Void) -> Void

    public var onStateChange: (@Sendable (PingviConnectionState) -> Void)?
    public var onPairingChange: (@Sendable (PingviPairingRecord?) -> Void)?
    public var onReply: ReplyHandler?
    public var onConversationRequest: ConversationHandler?
    public var onChatSend: ChatSendHandler?
    public var onCreateChat: CreateChatHandler?
    public var snapshotProvider: (@Sendable () -> PingviSnapshot)?

    public let identity: PingviDeviceIdentity
    public let serviceID: String
    public private(set) var pairing: PingviPairingRecord?

    private let queue = DispatchQueue(label: "app.pingvi.link.server")
    private var listener: NWListener?
    private var peer: PingviWirePeer?
    private var offer: PingviPairingOffer?
    private var failedAttempts: [String: [Date]] = [:]
    private var blockedUntil: [String: Date] = [:]

    public init(identity: PingviDeviceIdentity, serviceID: String, pairing: PingviPairingRecord? = nil) {
        self.identity = identity
        self.serviceID = serviceID
        self.pairing = pairing
    }

    public func start() throws {
        let listener = try NWListener(using: .tcp)
        listener.service = NWListener.Service(name: serviceID, type: PingviProtocol.serviceType)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.report(self.peer?.authenticated == true ? .connected : .searching)
            case .failed(let error): self.report(.disconnected("Локальный сервер: \(error.localizedDescription)"))
            case .cancelled: self.report(.stopped)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        queue.async { [weak self] in
            self?.peer?.connection.cancel()
            self?.peer = nil
            self?.listener?.cancel()
            self?.listener = nil
        }
    }

    public func makePairingOffer(lifetime: TimeInterval = 300) throws -> PingviPairingOffer {
        let value = try PingviCrypto.makePairingOffer(identity: identity, serviceID: serviceID, lifetime: lifetime)
        queue.sync { offer = value }
        return value
    }

    public func cancelPairingOffer() {
        queue.async { [weak self] in self?.offer = nil }
    }

    public func forgetDevice() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pairing = nil
            self.offer = nil
            self.peer?.connection.cancel()
            self.peer = nil
            self.onPairingChange?(nil)
            self.report(.searching)
        }
    }

    public func publish(_ snapshot: PingviSnapshot) {
        queue.async { [weak self] in self?.send(.snapshot(snapshot)) }
    }

    public func publish(_ result: PingviReplyResult) {
        queue.async { [weak self] in self?.send(.result(result)) }
    }

    private func accept(_ connection: NWConnection) {
        queue.async { [weak self] in
            guard let self else { return }
            let remote = self.remoteKey(connection)
            if self.peer != nil || (self.blockedUntil[remote] ?? .distantPast) > Date() {
                connection.cancel()
                return
            }
            let peer = PingviWirePeer(connection: connection)
            self.peer = peer
            self.report(.connecting)
            connection.stateUpdateHandler = { [weak self, weak peer] state in
                guard let self, let peer, self.peer === peer else { return }
                switch state {
                case .ready:
                    let timeout = DispatchWorkItem { [weak self, weak peer] in
                        guard let self, let peer, self.peer === peer, !peer.authenticated else { return }
                        self.recordAuthenticationFailure(for: peer.connection)
                        self.disconnect(peer, reason: "Время аутентификации истекло")
                    }
                    peer.authenticationTimeout = timeout
                    self.queue.asyncAfter(deadline: .now() + 10, execute: timeout)
                    self.receive(on: peer)
                case .failed(let error): self.disconnect(peer, reason: error.localizedDescription)
                case .cancelled: self.disconnect(peer, reason: "iPhone не подключён")
                default: break
                }
            }
            connection.start(queue: self.queue)
        }
    }

    private func receive(on peer: PingviWirePeer) {
        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak peer] data, _, complete, error in
            guard let self, let peer, self.peer === peer else { return }
            do {
                if let data, !data.isEmpty {
                    for frame in try peer.decoder.append(data) { try self.receive(frame, on: peer) }
                }
            } catch {
                if !peer.authenticated { self.recordAuthenticationFailure(for: peer.connection) }
                self.sendFailure(error.localizedDescription, on: peer)
                self.disconnect(peer, reason: error.localizedDescription)
                return
            }
            if let error { self.disconnect(peer, reason: error.localizedDescription); return }
            if complete { self.disconnect(peer, reason: "iPhone отключён"); return }
            self.receive(on: peer)
        }
    }

    private func receive(_ data: Data, on peer: PingviWirePeer) throws {
        if peer.authenticated {
            guard var cipher = peer.receiveCipher,
                  let sealed = try? JSONDecoder.pingvi.decode(PingviSealedFrame.self, from: data) else {
                throw PingviLinkError.invalidMessage
            }
            let plaintext = try cipher.open(sealed)
            peer.receiveCipher = cipher
            let message = try JSONDecoder.pingvi.decode(PingviMessage.self, from: plaintext)
            try validate(message)
            handle(message, on: peer)
            return
        }
        let handshake = try JSONDecoder.pingvi.decode(PingviHandshake.self, from: data)
        switch handshake.kind {
        case .pairRequest:
            guard let request = handshake.pairRequest, let offer else { throw PingviLinkError.invalidPairingOffer }
            let accepted = try PingviCrypto.acceptPairRequest(request, offer: offer, server: identity)
            let record = PingviPairingRecord(
                serviceID: serviceID,
                localDeviceID: identity.deviceID,
                peerDeviceID: request.deviceID,
                peerName: request.deviceName,
                pairingKey: accepted.pairingKey
            )
            pairing = record
            self.offer = nil
            sendHandshake(PingviHandshake(kind: .pairResponse, pairResponse: accepted.response), on: peer)
            onPairingChange?(record)
        case .clientHello:
            guard let hello = handshake.clientHello,
                  let pairing, pairing.peerDeviceID == hello.deviceID else {
                throw PingviLinkError.authenticationFailed
            }
            let accepted = try PingviCrypto.acceptClientHello(hello, pairingKey: pairing.pairingKey)
            sendHandshake(PingviHandshake(kind: .serverHello, serverHello: accepted.0), on: peer) { [weak self, weak peer] in
                guard let self, let peer, self.peer === peer else { return }
                peer.receiveCipher = PingviReceiveCipher(key: accepted.1)
                peer.sendCipher = PingviSendCipher(key: accepted.1)
                peer.authenticated = true
                peer.authenticationTimeout?.cancel()
                peer.authenticationTimeout = nil
                self.clearAuthenticationFailures(for: peer.connection)
                self.report(.connected)
                if let snapshot = self.snapshotProvider?() { self.send(.snapshot(snapshot)) }
            }
        default:
            throw PingviLinkError.invalidMessage
        }
    }

    private func handle(_ message: PingviMessage, on peer: PingviWirePeer) {
        switch message.kind {
        case .requestSnapshot:
            if let snapshot = snapshotProvider?() { send(.snapshot(snapshot)) }
        case .reply:
            guard let reply = message.reply else { return }
            guard let onReply else {
                send(.result(PingviReplyResult(commandID: message.id, status: .unavailable, message: "Ответы на Mac недоступны.")))
                return
            }
            onReply(message.id, reply) { [weak self] result in self?.queue.async { self?.send(.result(result)) } }
        case .requestConversation:
            guard let request = message.conversationRequest, let onConversationRequest else { return }
            onConversationRequest(message.id, request) { [weak self] response in
                self?.queue.async { self?.send(.conversation(response)) }
            }
        case .chatSend:
            guard let request = message.chatSendRequest, let onChatSend else { return }
            onChatSend(message.id, request) { [weak self] result in
                self?.queue.async { self?.send(.chatSendResult(result)) }
            }
        case .createChat:
            guard let request = message.createChatRequest, let onCreateChat else { return }
            onCreateChat(message.id, request) { [weak self] result in
                self?.queue.async { self?.send(.createChatResult(result)) }
            }
        case .ping:
            send(PingviMessage(kind: .pong))
        default:
            break
        }
    }

    private func send(_ message: PingviMessage) {
        guard let peer, peer.authenticated, var cipher = peer.sendCipher,
              let plaintext = try? JSONEncoder.pingvi.encode(message),
              let sealed = try? cipher.seal(plaintext),
              let encoded = try? JSONEncoder.pingvi.encode(sealed) else { return }
        peer.sendCipher = cipher
        sendFramed(encoded, on: peer)
    }

    private func validate(_ message: PingviMessage) throws {
        guard message.version == PingviProtocol.currentVersion else {
            throw PingviLinkError.incompatibleVersion(message.version)
        }
    }

    private func sendHandshake(_ value: PingviHandshake, on peer: PingviWirePeer, completion: (() -> Void)? = nil) {
        guard let data = try? JSONEncoder.pingvi.encode(value) else { return }
        sendFramed(data, on: peer, completion: completion)
    }

    private func sendFailure(_ message: String, on peer: PingviWirePeer) {
        sendHandshake(PingviHandshake(kind: .failure, error: message), on: peer)
    }

    private func sendFramed(_ data: Data, on peer: PingviWirePeer, completion: (() -> Void)? = nil) {
        guard let frame = try? PingviFraming.encode(data) else { return }
        peer.connection.send(content: frame, completion: .contentProcessed { _ in completion?() })
    }

    private func disconnect(_ candidate: PingviWirePeer, reason: String) {
        guard peer === candidate else { return }
        candidate.connection.cancel()
        candidate.authenticationTimeout?.cancel()
        candidate.authenticationTimeout = nil
        peer = nil
        report(.disconnected(reason))
    }

    private func recordAuthenticationFailure(for connection: NWConnection) {
        let remote = remoteKey(connection)
        let cutoff = Date().addingTimeInterval(-60)
        var attempts = (failedAttempts[remote] ?? []).filter { $0 > cutoff }
        attempts.append(Date())
        failedAttempts[remote] = attempts
        if attempts.count >= 3 { blockedUntil[remote] = Date().addingTimeInterval(60) }
    }

    private func clearAuthenticationFailures(for connection: NWConnection) {
        let remote = remoteKey(connection)
        failedAttempts.removeValue(forKey: remote)
        blockedUntil.removeValue(forKey: remote)
    }

    private func remoteKey(_ connection: NWConnection) -> String {
        if case .hostPort(let host, _) = connection.endpoint { return String(describing: host) }
        return String(describing: connection.endpoint)
    }

    private func report(_ state: PingviConnectionState) {
        onStateChange?(state)
    }
}

public final class PingviLinkClient: @unchecked Sendable {
    public var onStateChange: (@Sendable (PingviConnectionState) -> Void)?
    public var onPairingChange: (@Sendable (PingviPairingRecord?) -> Void)?
    public var onMessage: (@Sendable (PingviMessage) -> Void)?

    public let identity: PingviDeviceIdentity
    public private(set) var pairing: PingviPairingRecord?

    private let queue = DispatchQueue(label: "app.pingvi.link.client")
    private var browser: NWBrowser?
    private var peer: PingviWirePeer?
    private var pendingOffer: PingviPairingOffer?
    private var pendingPairRequest: PingviPairRequest?
    private var pendingPairingKey: Data?
    private var clientHello: PingviClientHello?
    private var shouldRun = false
    private var desiredServiceID: String?
    private var retryDelay: TimeInterval = 1
    private var retryWorkItem: DispatchWorkItem?
    private var heartbeat: DispatchSourceTimer?

    public init(identity: PingviDeviceIdentity, pairing: PingviPairingRecord? = nil) {
        self.identity = identity
        self.pairing = pairing
    }

    public func pair(using offer: PingviPairingOffer) {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = true
            self.desiredServiceID = offer.serviceID
            self.pendingOffer = offer
            self.startBrowsing(serviceID: offer.serviceID)
        }
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, let pairing = self.pairing else {
                self?.report(.stopped)
                return
            }
            self.shouldRun = true
            self.desiredServiceID = pairing.serviceID
            self.startBrowsing(serviceID: pairing.serviceID)
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.shouldRun = false
            self?.browser?.cancel()
            self?.browser = nil
            self?.peer?.connection.cancel()
            self?.peer = nil
            self?.cancelTimers()
            self?.report(.stopped)
        }
    }

    public func forgetMac() {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = false
            self.stopInternal()
            self.pairing = nil
            self.pendingOffer = nil
            self.onPairingChange?(nil)
            self.report(.stopped)
        }
    }

    public func requestSnapshot() {
        queue.async { [weak self] in self?.send(PingviMessage(kind: .requestSnapshot)) }
    }

    @discardableResult
    public func sendReply(_ reply: PingviReply, commandID: String = UUID().uuidString) -> String {
        queue.async { [weak self] in self?.send(.reply(reply, id: commandID)) }
        return commandID
    }

    @discardableResult
    public func requestConversation(sessionID: String, requestID: String = UUID().uuidString) -> String {
        queue.async { [weak self] in self?.send(.requestConversation(sessionID, id: requestID)) }
        return requestID
    }

    @discardableResult
    public func sendChat(_ request: PingviChatSendRequest, commandID: String = UUID().uuidString) -> String {
        queue.async { [weak self] in self?.send(.chatSend(request, id: commandID)) }
        return commandID
    }

    @discardableResult
    public func createChat(_ request: PingviCreateChatRequest, commandID: String = UUID().uuidString) -> String {
        queue.async { [weak self] in self?.send(.createChat(request, id: commandID)) }
        return commandID
    }

    public func sendPing() {
        queue.async { [weak self] in self?.send(PingviMessage(kind: .ping)) }
    }

    private func startBrowsing(serviceID: String) {
        stopInternal()
        report(.searching)
        let browser = NWBrowser(for: .bonjour(type: PingviProtocol.serviceType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .failed(let error) = state {
                self.report(.disconnected(error.localizedDescription))
                self.scheduleReconnect()
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, self.peer == nil,
                  let result = results.first(where: { Self.serviceName($0.endpoint) == serviceID }) else { return }
            self.connect(to: result.endpoint)
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    private static func serviceName(_ endpoint: NWEndpoint) -> String? {
        guard case .service(let name, _, _, _) = endpoint else { return nil }
        return name
    }

    private func connect(to endpoint: NWEndpoint) {
        report(.connecting)
        let connection = NWConnection(to: endpoint, using: .tcp)
        let peer = PingviWirePeer(connection: connection)
        self.peer = peer
        connection.stateUpdateHandler = { [weak self, weak peer] state in
            guard let self, let peer, self.peer === peer else { return }
            switch state {
            case .ready:
                self.browser?.cancel()
                self.browser = nil
                self.beginHandshake(on: peer)
                self.receive(on: peer)
            case .failed(let error): self.disconnect(peer, reason: error.localizedDescription)
            case .cancelled: self.disconnect(peer, reason: "Mac недоступен")
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func beginHandshake(on peer: PingviWirePeer) {
        if let offer = pendingOffer {
            do {
                let pair = try PingviCrypto.makePairRequest(offer: offer, client: identity)
                pendingPairRequest = pair.request
                pendingPairingKey = pair.pairingKey
                sendHandshake(PingviHandshake(kind: .pairRequest, pairRequest: pair.request), on: peer)
            } catch {
                disconnect(peer, reason: error.localizedDescription)
            }
        } else {
            sendClientHello(on: peer)
        }
    }

    private func sendClientHello(on peer: PingviWirePeer) {
        guard let pairing else { disconnect(peer, reason: "Mac не сопряжён"); return }
        let hello = PingviCrypto.makeClientHello(deviceID: identity.deviceID, pairingKey: pairing.pairingKey)
        clientHello = hello
        sendHandshake(PingviHandshake(kind: .clientHello, clientHello: hello), on: peer)
    }

    private func receive(on peer: PingviWirePeer) {
        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak peer] data, _, complete, error in
            guard let self, let peer, self.peer === peer else { return }
            do {
                if let data, !data.isEmpty {
                    for frame in try peer.decoder.append(data) { try self.receive(frame, on: peer) }
                }
            } catch {
                self.disconnect(peer, reason: error.localizedDescription)
                return
            }
            if let error { self.disconnect(peer, reason: error.localizedDescription); return }
            if complete { self.disconnect(peer, reason: "Mac отключён"); return }
            self.receive(on: peer)
        }
    }

    private func receive(_ data: Data, on peer: PingviWirePeer) throws {
        if peer.authenticated {
            guard var cipher = peer.receiveCipher,
                  let sealed = try? JSONDecoder.pingvi.decode(PingviSealedFrame.self, from: data) else {
                throw PingviLinkError.invalidMessage
            }
            let plaintext = try cipher.open(sealed)
            peer.receiveCipher = cipher
            let message = try JSONDecoder.pingvi.decode(PingviMessage.self, from: plaintext)
            guard message.version == PingviProtocol.currentVersion else {
                throw PingviLinkError.incompatibleVersion(message.version)
            }
            onMessage?(message)
            return
        }
        let handshake = try JSONDecoder.pingvi.decode(PingviHandshake.self, from: data)
        switch handshake.kind {
        case .pairResponse:
            guard let response = handshake.pairResponse,
                  let request = pendingPairRequest,
                  let key = pendingPairingKey,
                  let offer = pendingOffer else { throw PingviLinkError.invalidMessage }
            try PingviCrypto.verifyPairResponse(response, request: request, pairingKey: key)
            let record = PingviPairingRecord(
                serviceID: offer.serviceID,
                localDeviceID: identity.deviceID,
                peerDeviceID: response.deviceID,
                peerName: offer.macName,
                pairingKey: key
            )
            pairing = record
            pendingOffer = nil
            pendingPairRequest = nil
            pendingPairingKey = nil
            onPairingChange?(record)
            sendClientHello(on: peer)
        case .serverHello:
            guard let serverHello = handshake.serverHello,
                  let clientHello,
                  let pairing else { throw PingviLinkError.invalidMessage }
            let key = try PingviCrypto.acceptServerHello(serverHello, clientHello: clientHello, pairingKey: pairing.pairingKey)
            peer.receiveCipher = PingviReceiveCipher(key: key)
            peer.sendCipher = PingviSendCipher(key: key)
            peer.authenticated = true
            self.clientHello = nil
            retryDelay = 1
            startHeartbeat()
            report(.connected)
            send(PingviMessage(kind: .requestSnapshot))
        case .failure:
            throw NSError(domain: "PingviLink", code: 1, userInfo: [NSLocalizedDescriptionKey: handshake.error ?? "Mac отклонил соединение."])
        default:
            throw PingviLinkError.invalidMessage
        }
    }

    private func send(_ message: PingviMessage) {
        guard let peer, peer.authenticated, var cipher = peer.sendCipher,
              let plaintext = try? JSONEncoder.pingvi.encode(message),
              let sealed = try? cipher.seal(plaintext),
              let encoded = try? JSONEncoder.pingvi.encode(sealed) else { return }
        peer.sendCipher = cipher
        sendFramed(encoded, on: peer)
    }

    private func sendHandshake(_ value: PingviHandshake, on peer: PingviWirePeer) {
        guard let data = try? JSONEncoder.pingvi.encode(value) else { return }
        sendFramed(data, on: peer)
    }

    private func sendFramed(_ data: Data, on peer: PingviWirePeer) {
        guard let frame = try? PingviFraming.encode(data) else { return }
        peer.connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func disconnect(_ candidate: PingviWirePeer, reason: String) {
        guard peer === candidate else { return }
        candidate.connection.cancel()
        peer = nil
        heartbeat?.cancel()
        heartbeat = nil
        report(.disconnected(reason))
        scheduleReconnect()
    }

    private func stopInternal() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        browser?.cancel()
        browser = nil
        peer?.connection.cancel()
        peer = nil
        heartbeat?.cancel()
        heartbeat = nil
    }

    private func scheduleReconnect() {
        guard shouldRun, let serviceID = desiredServiceID else { return }
        retryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.shouldRun, self.peer == nil else { return }
            self.startBrowsing(serviceID: serviceID)
        }
        retryWorkItem = item
        queue.asyncAfter(deadline: .now() + retryDelay, execute: item)
        retryDelay = min(retryDelay * 2, 30)
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in self?.send(PingviMessage(kind: .ping)) }
        heartbeat = timer
        timer.resume()
    }

    private func cancelTimers() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        heartbeat?.cancel()
        heartbeat = nil
    }

    private func report(_ state: PingviConnectionState) {
        onStateChange?(state)
    }
}
