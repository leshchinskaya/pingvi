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

    /// Multi-select answers use the same ", " separator the Mac card writes and parses.
    static func joined(_ selection: [String], in field: PingviQuestionField) -> String {
        field.options.map(\.label).filter(selection.contains).joined(separator: ", ")
    }
}

enum MobileSnapshotUpdater {
    static func recording(_ conversation: PingviConversation, in snapshot: PingviSnapshot) -> PingviSnapshot {
        let sessions = snapshot.sessions.map { session in
            guard session.id == conversation.sessionID, session.status != conversation.status else { return session }
            return PingviSessionSummary(
                id: session.id,
                title: session.title,
                project: session.project,
                projectPath: session.projectPath,
                agent: session.agent,
                source: session.source,
                status: conversation.status,
                preview: PingviSessionStatus(rawStatus: conversation.status) == .viewed ? String(localized: "Результат просмотрен") : session.preview,
                updatedAt: session.updatedAt
            )
        }
        let completions = PingviSessionStatus(rawStatus: conversation.status) == .viewed
            ? snapshot.completions.filter { $0.id != conversation.sessionID }
            : snapshot.completions
        return PingviSnapshot(
            revision: snapshot.revision,
            generatedAt: snapshot.generatedAt,
            questions: snapshot.questions,
            completions: completions,
            sessions: sessions,
            projects: snapshot.projects
        )
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
    @Published private(set) var markingReadSessions: Set<String> = []
    @Published private(set) var creatingChat = false
    @Published var createdSessionID: String?
    @Published var createChatError: String?
    /// Blocking problems that need a decision (pairing). Everything else goes to toasts or inline errors.
    @Published var errorMessage: String?
    @Published private(set) var toast: MobileToast?
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var replyFailures: [String: MobileReplyFailure] = [:]
    @Published private(set) var chatFailures: [String: MobileChatFailure] = [:]
    @Published private(set) var conversationErrors: [String: String] = [:]

    let watch = PhoneWatchBridge()
    private let keychain = PingviKeychain(service: "app.pingvi.mobile.link")
    private let client: PingviLinkClient
    private let cacheURL: URL
    private let logger = Logger(subsystem: "app.pingvi.mobile", category: "Link")
    private var replySessionsByCommand: [String: String] = [:]
    private var repliesByCommand: [String: PingviReply] = [:]
    private var chatTextsBySession: [String: String] = [:]
    private static let lastSyncKey = "lastSnapshotAt"

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
        lastSyncAt = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        configureClient()
#if DEBUG
        if MobileDocumentationPreview.isEnabled {
            self.pairing = MobileDocumentationPreview.pairing
            self.snapshot = MobileDocumentationPreview.snapshot
            self.conversations = MobileDocumentationPreview.delaysConversationFixture ? [:] : MobileDocumentationPreview.conversations
            self.state = MobileDocumentationPreview.simulatesOffline ? .disconnected("Mac недоступен") : .connected
            self.lastSyncAt = Date().addingTimeInterval(MobileDocumentationPreview.simulatesOffline ? -300 : 0)
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

    /// Manual retry from the connection banner.
    func reconnect() {
#if DEBUG
        if MobileDocumentationPreview.isEnabled { return }
#endif
        guard pairing != nil, state != .connected else { return activate() }
        client.start()
    }

    func showToast(_ text: String, style: MobileToast.Style = .info) {
        toast = MobileToast(text: text, style: style)
        if style == .failure { MobileHaptics.warning() }
    }

    func dismissToast(_ id: UUID) {
        if toast?.id == id { toast = nil }
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
            showToast(String(localized: "Ответ можно отправить только при связи с Mac."), style: .failure)
            return String(localized: "Mac недоступен")
        }
        guard let question = snapshot.questions.first(where: { $0.id == reply.sessionID && $0.token == reply.questionToken && $0.canReply }) else {
            replyFailures[reply.sessionID] = nil
            showToast(String(localized: "Вопрос уже закрыт или изменился."), style: .failure)
            return String(localized: "Вопрос устарел")
        }
        let commandID = client.sendReply(MobileReplyBuilder.normalized(reply, for: question))
        replySessionsByCommand[commandID] = reply.sessionID
        repliesByCommand[commandID] = reply
        replyFailures[reply.sessionID] = nil
        replyingSessions.insert(reply.sessionID)
        commandResults[commandID] = PingviReplyResult(commandID: commandID, status: .checking, message: String(localized: "Отправляем…"))
        return String(localized: "Отправляем…")
    }

    func retryReply(sessionID: String) {
        guard let failure = replyFailures[sessionID] else { return }
        send(failure.reply)
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
        markingReadSessions = []
        replyFailures = [:]
        chatFailures = [:]
        conversationErrors = [:]
        repliesByCommand = [:]
        chatTextsBySession = [:]
        lastSyncAt = nil
        UserDefaults.standard.removeObject(forKey: Self.lastSyncKey)
        MobileRouter.shared.reset()
        try? keychain.remove("paired-mac")
        try? FileManager.default.removeItem(at: cacheURL)
        watch.update(snapshot: snapshot, connection: .stopped)
    }

    func loadConversation(sessionID: String, force: Bool = false) {
        guard state == .connected else {
            if conversations[sessionID] == nil {
                conversationErrors[sessionID] = String(localized: "Переписка загрузится, когда появится связь с Mac.")
            }
            return
        }
        guard force || (conversations[sessionID] == nil && !loadingConversations.contains(sessionID)) else { return }
        conversationErrors[sessionID] = nil
        loadingConversations.insert(sessionID)
        _ = client.requestConversation(sessionID: sessionID)
    }

    func markConversationRead(sessionID: String) {
        guard state == .connected else {
            showToast(String(localized: "Отметить прочитанным можно только при связи с Mac."), style: .failure)
            return
        }
        guard snapshot.sessions.contains(where: { $0.id == sessionID && $0.sessionStatus.isUnreadResult }),
              !markingReadSessions.contains(sessionID) else { return }
        markingReadSessions.insert(sessionID)
        loadConversation(sessionID: sessionID, force: true)
    }

    func sendChat(sessionID: String, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == .connected else {
            chatFailures[sessionID] = MobileChatFailure(text: text, message: String(localized: "Нет связи с Mac"))
            return
        }
        guard let conversation = conversations[sessionID], conversation.canSend, !text.isEmpty else {
            let reason = conversations[sessionID]?.reason ?? ""
            chatFailures[sessionID] = MobileChatFailure(
                text: text,
                message: reason.isEmpty ? String(localized: "Диалог сейчас не принимает сообщения") : reason
            )
            return
        }
        chatFailures[sessionID] = nil
        chatTextsBySession[sessionID] = text
        sendingChats.insert(sessionID)
        _ = client.sendChat(PingviChatSendRequest(
            sessionID: sessionID,
            conversationToken: conversation.token,
            text: text
        ))
    }

    func retryChat(sessionID: String) {
        guard let failure = chatFailures[sessionID] else { return }
        sendChat(sessionID: sessionID, text: failure.text)
    }

    func discardChatFailure(sessionID: String) {
        chatFailures[sessionID] = nil
    }

    func createChat(agent: String, projectPath: String, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == .connected else {
            createChatError = String(localized: "Новый диалог можно создать только при связи с Mac.")
            return
        }
        guard !projectPath.isEmpty, !text.isEmpty, !creatingChat else { return }
        createChatError = nil
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
            recordSync()
            let availableSessions = Set(incoming.sessions.map(\.id))
            conversations = conversations.filter { availableSessions.contains($0.key) }
            let openTokens = Set(incoming.questions.map(\.token))
            replyFailures = replyFailures.filter { openTokens.contains($0.value.reply.questionToken) }
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
                let reply = repliesByCommand[result.commandID]
                if !result.status.keepsSubmissionPending,
                   let sessionID = replySessionsByCommand.removeValue(forKey: result.commandID) {
                    replyingSessions.remove(sessionID)
                    repliesByCommand[result.commandID] = nil
                }
                switch result.status {
                case .failed, .unavailable, .uncertain:
                    if let reply { replyFailures[reply.sessionID] = MobileReplyFailure(reply: reply, message: result.message) }
                    MobileHaptics.warning()
                case .stale:
                    showToast(result.message, style: .failure)
                case .checking:
                    MobileHaptics.success()
                default:
                    break
                }
            }
        case .conversation:
            guard let response = message.conversationResponse else { return }
            loadingConversations.remove(response.sessionID)
            markingReadSessions.remove(response.sessionID)
            if let conversation = response.conversation {
                conversationErrors[response.sessionID] = nil
                conversations[response.sessionID] = conversation
                snapshot = MobileSnapshotUpdater.recording(conversation, in: snapshot)
                persist(snapshot)
                watch.update(snapshot: snapshot, connection: state)
            } else if let error = response.error {
                conversationErrors[response.sessionID] = error
            }
        case .chatSendResult:
            guard let result = message.chatSendResult else { return }
            sendingChats.remove(result.sessionID)
            let text = chatTextsBySession.removeValue(forKey: result.sessionID) ?? ""
            if result.status == .failed || result.status == .stale || result.status == .uncertain {
                chatFailures[result.sessionID] = MobileChatFailure(text: text, message: result.message)
                MobileHaptics.warning()
            } else {
                MobileHaptics.success()
            }
            loadConversation(sessionID: result.sessionID, force: true)
        case .createChatResult:
            guard let result = message.createChatResult else { return }
            creatingChat = false
            if let session = result.session {
                createdSessionID = session.id
                client.requestSnapshot()
            } else {
                createChatError = result.error ?? String(localized: "Не удалось создать диалог.")
            }
        default:
            break
        }
    }

    private func recordSync() {
        let now = Date()
        lastSyncAt = now
        UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
    }

    private func persist(_ value: PingviSnapshot) {
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: cacheURL, options: [.atomic, .completeFileProtection])
        } catch { logger.error("Snapshot cache write failed: \(error.localizedDescription, privacy: .public)") }
    }
}
