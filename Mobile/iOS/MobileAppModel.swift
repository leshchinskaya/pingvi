import Foundation
import OSLog
import PingviLink
import UIKit

private struct StoredMobileIdentity: Codable {
    let deviceID: String
    let privateKey: Data
}

enum MobileReplyBuilder {
    static func normalized(_ reply: PingviReply, for question: PingviQuestion) -> PingviReply {
        guard question.options.isEmpty,
              question.fields.contains(where: { $0.id == "text" && $0.options.isEmpty }),
              reply.fieldAnswers["text", default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !reply.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return reply
        }
        var fields = reply.fieldAnswers
        fields["text"] = reply.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return PingviReply(sessionID: reply.sessionID, questionToken: reply.questionToken, answer: "", fieldAnswers: fields)
    }
}

@MainActor
final class MobileAppModel: ObservableObject {
    static let shared = MobileAppModel()

    @Published private(set) var state: PingviConnectionState = .stopped
    @Published private(set) var pairing: PingviPairingRecord?
    @Published private(set) var snapshot = PingviSnapshot(revision: 0, questions: [])
    @Published private(set) var commandResults: [String: PingviReplyResult] = [:]
    @Published private(set) var replyingSessions: Set<String> = []
    @Published private(set) var conversations: [String: PingviConversation] = [:]
    @Published private(set) var loadingConversations: Set<String> = []
    @Published private(set) var sendingChats: Set<String> = []
    @Published private(set) var creatingChat = false
    @Published var createdSessionID: String?
    @Published var errorMessage: String?

    let watch = PhoneWatchBridge()
    private let keychain = PingviKeychain(service: "app.pingvi.mobile.link")
    private let client: PingviLinkClient
    private let cacheURL: URL
    private let logger = Logger(subsystem: "app.pingvi.mobile", category: "Link")
    private var replySessionsByCommand: [String: String] = [:]

    private init() {
        let saved = keychain.codable(StoredMobileIdentity.self, for: "identity")
        let identity = PingviDeviceIdentity(
            deviceID: saved?.deviceID ?? UUID().uuidString,
            deviceName: UIDevice.current.name,
            privateKey: saved?.privateKey
        )
        if saved == nil {
            try? keychain.setCodable(StoredMobileIdentity(deviceID: identity.deviceID, privateKey: identity.privateKey), for: "identity")
        }
        let pairing = keychain.codable(PingviPairingRecord.self, for: "paired-mac")
        self.pairing = pairing
        self.client = PingviLinkClient(identity: identity, pairing: pairing)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.cacheURL = base.appendingPathComponent("Pingvi/mobile-snapshot.json")
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(PingviSnapshot.self, from: data) {
            snapshot = cached
        }
        configureClient()
#if DEBUG
        if MobileDocumentationPreview.isEnabled {
            self.pairing = MobileDocumentationPreview.pairing
            self.snapshot = MobileDocumentationPreview.snapshot
            self.conversations = MobileDocumentationPreview.delaysConversationFixture ? [:] : MobileDocumentationPreview.conversations
            self.state = .connected
            if MobileDocumentationPreview.delaysConversationFixture {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    self?.conversations = MobileDocumentationPreview.conversations
                }
            }
        }
#endif
        watch.onReply = { [weak self] reply, completion in
            Task { @MainActor in
                guard let self else { return }
                completion(self.send(reply))
            }
        }
        watch.activate()
    }

    var isPaired: Bool { pairing != nil }
    var questions: [PingviQuestion] { snapshot.questions.sorted { $0.arrivedAt < $1.arrivedAt } }
    var sessions: [PingviSessionSummary] { snapshot.sessions.sorted { $0.updatedAt > $1.updatedAt } }

    func activate() {
#if DEBUG
        if MobileDocumentationPreview.isEnabled { return }
#endif
        if state == .connected { client.requestSnapshot() }
        else if pairing != nil { client.start() }
    }

    func enteredBackground() {
        // Keep the connection alive only for the background time iOS grants naturally.
        watch.update(snapshot: snapshot, connection: state)
    }

    func pair(qrValue: String) {
        do {
            guard let url = URL(string: qrValue) else { throw PingviLinkError.invalidPairingOffer }
            let offer = try PingviPairingOffer.decode(url: url)
            errorMessage = nil
            client.pair(using: offer)
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func send(_ reply: PingviReply) -> String {
        guard state == .connected else {
            errorMessage = "Ответ можно отправить только при активном соединении с Mac."
            return "Mac недоступен"
        }
        guard let question = snapshot.questions.first(where: { $0.id == reply.sessionID && $0.token == reply.questionToken && $0.canReply }) else {
            errorMessage = "Вопрос уже изменился или больше не принимает ответы."
            return "Вопрос устарел"
        }
        let commandID = client.sendReply(MobileReplyBuilder.normalized(reply, for: question))
        replySessionsByCommand[commandID] = reply.sessionID
        replyingSessions.insert(reply.sessionID)
        commandResults[commandID] = PingviReplyResult(commandID: commandID, status: .checking, message: "Отправляем…")
        return "Отправляем…"
    }

    func forgetMac() {
        client.forgetMac()
        pairing = nil
        snapshot = PingviSnapshot(revision: 0, questions: [])
        commandResults = [:]
        replyingSessions = []
        replySessionsByCommand = [:]
        conversations = [:]
        loadingConversations = []
        sendingChats = []
        try? keychain.remove("paired-mac")
        try? FileManager.default.removeItem(at: cacheURL)
        watch.update(snapshot: snapshot, connection: .stopped)
    }

    func loadConversation(sessionID: String, force: Bool = false) {
        guard state == .connected else {
            if conversations[sessionID] == nil { errorMessage = "Историю можно загрузить только при активном соединении с Mac." }
            return
        }
        guard force || (conversations[sessionID] == nil && !loadingConversations.contains(sessionID)) else { return }
        loadingConversations.insert(sessionID)
        _ = client.requestConversation(sessionID: sessionID)
    }

    func sendChat(sessionID: String, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == .connected else {
            errorMessage = "Сообщение можно отправить только при активном соединении с Mac."
            return
        }
        guard let conversation = conversations[sessionID], conversation.canSend, !text.isEmpty else {
            errorMessage = conversations[sessionID]?.reason ?? "Диалог сейчас не принимает сообщения."
            return
        }
        sendingChats.insert(sessionID)
        _ = client.sendChat(PingviChatSendRequest(
            sessionID: sessionID,
            conversationToken: conversation.token,
            text: text
        ))
    }

    func createChat(agent: String, projectPath: String, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == .connected else {
            errorMessage = "Новый диалог можно создать только при активном соединении с Mac."
            return
        }
        guard !projectPath.isEmpty, !text.isEmpty, !creatingChat else { return }
        creatingChat = true
        createdSessionID = nil
        _ = client.createChat(PingviCreateChatRequest(agent: agent, projectPath: projectPath, text: text))
    }

    func diagnostics() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return [
            "Pingvi Mobile \(version)",
            UIDevice.current.systemName + " " + UIDevice.current.systemVersion,
            "Connection: \(state.description)",
            "Paired: \(pairing != nil)",
            "Snapshot revision: \(snapshot.revision)",
            "Pending questions: \(snapshot.questions.count)"
        ].joined(separator: "\n")
    }

    private func configureClient() {
        client.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.logger.info("State: \(state.description, privacy: .public)")
                self?.state = state
                if let self { self.watch.update(snapshot: self.snapshot, connection: state) }
            }
        }
        client.onPairingChange = { [weak self] pairing in
            Task { @MainActor in
                guard let self else { return }
                self.pairing = pairing
                if let pairing {
                    do { try self.keychain.setCodable(pairing, for: "paired-mac") }
                    catch { self.errorMessage = error.localizedDescription }
                    MobileNotifications.shared.requestAuthorization()
                } else {
                    try? self.keychain.remove("paired-mac")
                }
            }
        }
        client.onMessage = { [weak self] message in
            Task { @MainActor in self?.receive(message) }
        }
    }

    private func receive(_ message: PingviMessage) {
        switch message.kind {
        case .snapshot:
            guard let incoming = message.snapshot, incoming.revision >= snapshot.revision else { return }
            let oldTokens = Set(snapshot.questions.map(\.token))
            let oldCompletions = Set(snapshot.completions.map(\.id))
            snapshot = incoming
            let availableSessions = Set(incoming.sessions.map(\.id))
            conversations = conversations.filter { availableSessions.contains($0.key) }
            logger.debug("Received revision \(incoming.revision, privacy: .public), pending \(incoming.questions.count, privacy: .public)")
            persist(incoming)
            for question in incoming.questions where !oldTokens.contains(question.token) {
                MobileNotifications.shared.show(question: question)
            }
            for completion in incoming.completions where !oldCompletions.contains(completion.id) {
                MobileNotifications.shared.show(completion: completion)
            }
            watch.update(snapshot: incoming, connection: state)
        case .replyResult:
            if let result = message.replyResult {
                commandResults[result.commandID] = result
                if !result.status.keepsSubmissionPending,
                   let sessionID = replySessionsByCommand.removeValue(forKey: result.commandID) {
                    replyingSessions.remove(sessionID)
                }
                if result.status == .failed || result.status == .stale || result.status == .unavailable || result.status == .uncertain {
                    errorMessage = result.message
                }
            }
        case .conversation:
            guard let response = message.conversationResponse else { return }
            loadingConversations.remove(response.sessionID)
            if let conversation = response.conversation {
                conversations[response.sessionID] = conversation
            } else if let error = response.error {
                errorMessage = error
            }
        case .chatSendResult:
            guard let result = message.chatSendResult else { return }
            sendingChats.remove(result.sessionID)
            if result.status == .failed || result.status == .stale || result.status == .uncertain {
                errorMessage = result.message
            }
            loadConversation(sessionID: result.sessionID, force: true)
        case .createChatResult:
            guard let result = message.createChatResult else { return }
            creatingChat = false
            if let session = result.session {
                createdSessionID = session.id
                client.requestSnapshot()
            } else {
                errorMessage = result.error ?? "Не удалось создать диалог."
            }
        default:
            break
        }
    }

    private func persist(_ value: PingviSnapshot) {
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: cacheURL, options: [.atomic, .completeFileProtection])
        } catch { errorMessage = "Кэш: \(error.localizedDescription)" }
    }
}
