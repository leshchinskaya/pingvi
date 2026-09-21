import AppKit
import CoreImage.CIFilterBuiltins
import Foundation
import OSLog
import PingviLink
import ServiceManagement

private struct StoredLinkIdentity: Codable {
    let deviceID: String
    let privateKey: Data
}

private struct PendingMobileReply {
    let commandID: String
    let sessionID: String
    let token: String
}

final class MacMobileLink: ObservableObject, @unchecked Sendable {
    @Published private(set) var state: PingviConnectionState = .stopped
    @Published private(set) var pairedDevice: PingviPairingRecord?
    @Published private(set) var pairingOffer: PingviPairingOffer?
    @Published private(set) var lastError: String?

    private let store: Store
    private let keychain: PingviKeychain
    private let server: PingviLinkServer?
    private var revision: UInt64 = 0
    private var pending: [String: PendingMobileReply] = [:]
    private let isPreview: Bool
    private let logger = Logger(subsystem: "app.pingvi.mac", category: "MobileLink")

    init(store: Store, preview: Bool = false) {
        self.store = store
        self.isPreview = preview
        self.keychain = PingviKeychain(service: "app.pingvi.mac.link")
        if preview {
            server = nil
            state = .searching
            return
        }

        let savedIdentity = keychain.codable(StoredLinkIdentity.self, for: "identity")
        let identity = PingviDeviceIdentity(
            deviceID: savedIdentity?.deviceID ?? UUID().uuidString,
            deviceName: Host.current().localizedName ?? "Mac",
            privateKey: savedIdentity?.privateKey
        )
        if savedIdentity == nil {
            try? keychain.setCodable(
                StoredLinkIdentity(deviceID: identity.deviceID, privateKey: identity.privateKey),
                for: "identity"
            )
        }
        let serviceID: String
        if let saved = keychain.data(for: "service-id").flatMap({ String(data: $0, encoding: .utf8) }) {
            serviceID = saved
        } else {
            serviceID = "pingvi-" + UUID().uuidString.lowercased()
            try? keychain.set(Data(serviceID.utf8), for: "service-id")
        }
        let pairing = keychain.codable(PingviPairingRecord.self, for: "paired-device")
        pairedDevice = pairing
        let server = PingviLinkServer(identity: identity, serviceID: serviceID, pairing: pairing)
        self.server = server
        configure(server)
    }

    func start() {
        guard !isPreview, let server else { return }
        do { try server.start() }
        catch {
            logger.error("Listener failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            state = .disconnected(error.localizedDescription)
        }
    }

    func beginPairing() {
        guard let server else { return }
        do {
            pairingOffer = try server.makePairingOffer()
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }

    func cancelPairing() {
        pairingOffer = nil
        server?.cancelPairingOffer()
    }

    func forgetDevice() {
        try? keychain.remove("paired-device")
        pairingOffer = nil
        pairedDevice = nil
        server?.forgetDevice()
    }

    func storeDidChange() {
        guard !isPreview else { return }
        revision += 1
        logger.debug("Publishing revision \(self.revision, privacy: .public), pending \(self.store.pending.count, privacy: .public)")
        resolvePendingReplies()
        server?.publish(snapshot())
    }

    func qrImage(size: CGFloat = 260) -> NSImage? {
        guard let string = pairingOffer?.url?.absoluteString,
              let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.integral
        let scale = min(size / extent.width, size / extent.height)
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: transformed)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        image.isTemplate = false
        return image
    }

    static func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }

    private func configure(_ server: PingviLinkServer) {
        server.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.logger.info("State: \(state.description, privacy: .public)")
                self?.state = state
            }
        }
        server.onPairingChange = { [weak self] pairing in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pairedDevice = pairing
                self.logger.info("Pairing changed; paired=\(pairing != nil, privacy: .public)")
                self.pairingOffer = nil
                if let pairing { try? self.keychain.setCodable(pairing, for: "paired-device") }
                else { try? self.keychain.remove("paired-device") }
            }
        }
        server.snapshotProvider = { [weak self] in
            if Thread.isMainThread { return self?.snapshot() ?? PingviSnapshot(revision: 0, questions: []) }
            return DispatchQueue.main.sync { self?.snapshot() ?? PingviSnapshot(revision: 0, questions: []) }
        }
        server.onReply = { [weak self] commandID, reply, completion in
            DispatchQueue.main.async { self?.handle(commandID: commandID, reply: reply, completion: completion) }
        }
        server.onConversationRequest = { [weak self] requestID, request, completion in
            DispatchQueue.main.async { self?.handle(requestID: requestID, conversation: request, completion: completion) }
        }
        server.onChatSend = { [weak self] commandID, request, completion in
            DispatchQueue.main.async { self?.handle(commandID: commandID, chat: request, completion: completion) }
        }
        server.onCreateChat = { [weak self] commandID, request, completion in
            DispatchQueue.main.async { self?.handle(commandID: commandID, create: request, completion: completion) }
        }
    }

    private func snapshot() -> PingviSnapshot {
        let questions = store.pending.compactMap { session -> PingviQuestion? in
            guard let state = PingviQuestionState(rawValue: session.status) else { return nil }
            let arrival = store.local.arrival[session.token].map(Date.init(timeIntervalSince1970:)) ?? Date(timeIntervalSince1970: session.updated)
            let mobileCanReply = session.canReply && state == .waiting && !session.fields.contains(where: \.multi)
            return PingviQuestion(
                id: session.id,
                token: session.token,
                title: store.title(session),
                project: URL(fileURLWithPath: session.project).lastPathComponent,
                agent: session.agent,
                source: session.source,
                question: session.question,
                context: session.detail,
                options: session.options.map { PingviOption(id: $0.id, label: $0.label) },
                fields: session.fields.map { field in
                    PingviQuestionField(
                        id: field.id,
                        label: field.label,
                        options: field.options.map { PingviOption(id: $0.label, label: $0.label) },
                        allowsMultiple: field.multi
                    )
                },
                state: state,
                canReply: mobileCanReply,
                arrivedAt: arrival
            )
        }
        let completions = store.visible.filter { $0.status == "done" }.map { session in
            PingviCompletion(
                id: session.id,
                title: store.title(session),
                agent: session.agent,
                source: session.source,
                summary: "Агент закончил ответ.",
                completedAt: Date(timeIntervalSince1970: session.updated)
            )
        }
        let sessions = store.visible.map(summary)
        let projectPaths = Set(store.visible.map(\.project).filter { !$0.isEmpty })
            .union(ChatPreferences.shared.saved.recentProjects.filter { !$0.isEmpty })
        let projects = projectPaths.sorted().map {
            PingviProject(name: URL(fileURLWithPath: $0).lastPathComponent, path: $0)
        }
        return PingviSnapshot(
            revision: revision,
            questions: questions,
            completions: completions,
            sessions: sessions,
            projects: projects
        )
    }

    private func summary(_ session: Session) -> PingviSessionSummary {
        let preview: String
        switch session.status {
        case "waiting", "checking", "unconfirmed": preview = session.question.isEmpty ? session.statusLabel : session.question
        case "working": preview = "Агент работает…"
        case "done": preview = "Готовый результат · не просмотрен"
        case "viewed": preview = "Результат просмотрен"
        case "offline": preview = "Исходная сессия сейчас недоступна"
        default: preview = session.statusLabel
        }
        return PingviSessionSummary(
            id: session.id,
            title: store.title(session),
            project: session.project.isEmpty ? session.source : URL(fileURLWithPath: session.project).lastPathComponent,
            projectPath: session.project,
            agent: session.agent,
            source: session.source,
            status: session.status,
            preview: preview,
            updatedAt: Date(timeIntervalSince1970: session.updated)
        )
    }

    private func handle(
        requestID: String,
        conversation request: PingviConversationRequest,
        completion: @escaping @Sendable (PingviConversationResponse) -> Void
    ) {
        guard let session = store.visible.first(where: { $0.id == request.sessionID }) else {
            completion(PingviConversationResponse(requestID: requestID, sessionID: request.sessionID, error: "Диалог больше недоступен."))
            return
        }
        store.markViewed(session)
        loadConversation(session: session, requestID: requestID, completion: completion)
    }

    private func loadConversation(
        session: Session,
        requestID: String,
        completion: @escaping @Sendable (PingviConversationResponse) -> Void
    ) {
        Bridge.call(["action": "chat-history", "session": ChatModel.payload(session)]) { [weak self] result in
            guard let self else { return }
            do {
                let history = try JSONDecoder().decode(ChatHistory.self, from: result.get())
                completion(PingviConversationResponse(
                    requestID: requestID,
                    sessionID: session.id,
                    conversation: self.mobileConversation(session: session, history: history)
                ))
            } catch {
                self.loadReadOnlyConversation(session: session, requestID: requestID, originalError: error, completion: completion)
            }
        }
    }

    private func loadReadOnlyConversation(
        session: Session,
        requestID: String,
        originalError: Error,
        completion: @escaping @Sendable (PingviConversationResponse) -> Void
    ) {
        Bridge.call(["action": "search-history", "session": ChatModel.payload(session)]) { [weak self] result in
            guard let self else { return }
            do {
                let history = try JSONDecoder().decode(SearchHistory.self, from: result.get())
                guard history.available else { throw originalError }
                let conversation = PingviConversation(
                    sessionID: session.id,
                    title: self.store.title(session),
                    project: session.project.isEmpty ? session.source : URL(fileURLWithPath: session.project).lastPathComponent,
                    agent: session.agent,
                    source: session.source,
                    status: session.status,
                    messages: history.messages.map(self.mobileMessage),
                    partial: history.partial,
                    context: "",
                    canSend: false,
                    busy: session.status == "working",
                    reason: "История доступна только для чтения; исходная сессия сейчас не готова принимать сообщения.",
                    token: "",
                    pending: false
                )
                completion(PingviConversationResponse(requestID: requestID, sessionID: session.id, conversation: conversation))
            } catch {
                completion(PingviConversationResponse(
                    requestID: requestID,
                    sessionID: session.id,
                    error: originalError.localizedDescription
                ))
            }
        }
    }

    private func mobileConversation(session: Session, history: ChatHistory) -> PingviConversation {
        let current = store.visible.first(where: { $0.id == session.id }) ?? session
        return PingviConversation(
            sessionID: session.id,
            title: store.title(current),
            project: current.project.isEmpty ? current.source : URL(fileURLWithPath: current.project).lastPathComponent,
            agent: current.agent,
            source: current.source,
            status: current.status,
            messages: history.messages.map(mobileMessage),
            partial: history.partial,
            context: history.context,
            canSend: history.canSend,
            busy: history.busy,
            reason: history.reason,
            token: history.token,
            pending: history.pending
        )
    }

    private func mobileMessage(_ message: ChatMessage) -> PingviChatMessage {
        PingviChatMessage(
            id: message.id,
            role: message.role == "user" ? .user : .assistant,
            text: message.text,
            state: PingviChatMessageState(rawValue: message.state) ?? .received
        )
    }

    private func handle(
        commandID: String,
        chat request: PingviChatSendRequest,
        completion: @escaping @Sendable (PingviChatSendResult) -> Void
    ) {
        guard let session = store.visible.first(where: { $0.id == request.sessionID }) else {
            completion(PingviChatSendResult(commandID: commandID, sessionID: request.sessionID, status: .stale, message: "Диалог больше недоступен."))
            return
        }
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(PingviChatSendResult(commandID: commandID, sessionID: request.sessionID, status: .failed, message: "Напишите сообщение."))
            return
        }
        Bridge.call([
            "action": "chat-send",
            "session": ChatModel.payload(session),
            "text": request.text,
            "token": request.conversationToken,
            "requestID": commandID
        ]) { [weak self] result in
            guard let self else { return }
            do {
                let receipt = try JSONDecoder().decode(ChatReceipt.self, from: result.get())
                let status: PingviChatSendStatus = receipt.state == "submitted" ? .submitted : .uncertain
                completion(PingviChatSendResult(
                    commandID: commandID,
                    sessionID: session.id,
                    status: status,
                    message: receipt.error ?? (status == .submitted ? "Сообщение передано агенту." : "Результат отправки неизвестен.")
                ))
                self.store.poll()
            } catch {
                completion(PingviChatSendResult(commandID: commandID, sessionID: session.id, status: .failed, message: error.localizedDescription))
            }
        }
    }

    private func handle(
        commandID: String,
        create request: PingviCreateChatRequest,
        completion: @escaping @Sendable (PingviCreateChatResult) -> Void
    ) {
        let allowedProjects = Set(store.visible.map(\.project).filter { !$0.isEmpty })
            .union(ChatPreferences.shared.saved.recentProjects.filter { !$0.isEmpty })
        guard allowedProjects.contains(request.projectPath), ["codex", "claude"].contains(request.agent) else {
            completion(PingviCreateChatResult(commandID: commandID, error: "Выберите доступный проект и агента."))
            return
        }
        Bridge.call([
            "action": "chat-create",
            "agent": request.agent,
            "project": request.projectPath,
            "text": request.text,
            "requestID": commandID
        ]) { [weak self] result in
            guard let self else { return }
            do {
                let created = try JSONDecoder().decode(CreatedChat.self, from: result.get())
                if !self.store.local.sessions.contains(where: { $0.id == created.session.id }) {
                    self.store.local.sessions.append(created.session)
                }
                self.store.save()
                self.store.poll()
                completion(PingviCreateChatResult(commandID: commandID, session: self.summary(created.session)))
            } catch {
                completion(PingviCreateChatResult(commandID: commandID, error: error.localizedDescription))
            }
        }
    }

    private func handle(commandID: String, reply: PingviReply, completion: @escaping @Sendable (PingviReplyResult) -> Void) {
        guard state == .connected else {
            completion(PingviReplyResult(commandID: commandID, status: .unavailable, message: "Mac не подключён."))
            return
        }
        guard let session = store.visible.first(where: { $0.id == reply.sessionID }),
              session.token == reply.questionToken else {
            completion(PingviReplyResult(commandID: commandID, status: .stale, message: "Вопрос уже изменился."))
            return
        }
        guard session.status == "waiting", session.canReply, !session.fields.contains(where: \.multi) else {
            completion(PingviReplyResult(commandID: commandID, status: .unavailable, message: "Этот вопрос сейчас нельзя отправить."))
            return
        }
        pending[commandID] = PendingMobileReply(commandID: commandID, sessionID: session.id, token: session.token)
        store.reply(session, answer: reply.answer, fieldAnswers: reply.fieldAnswers) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                completion(PingviReplyResult(commandID: commandID, status: .checking, message: "Ответ отправлен · проверяем"))
            case .failure(let error):
                self.pending.removeValue(forKey: commandID)
                let uncertain = self.store.visible.first(where: { $0.id == session.id })?.status == "unconfirmed"
                completion(PingviReplyResult(
                    commandID: commandID,
                    status: uncertain ? .uncertain : .failed,
                    message: uncertain ? "Результат отправки неизвестен." : error.localizedDescription
                ))
            }
        }
    }

    private func resolvePendingReplies() {
        for item in Array(pending.values) {
            let current = store.visible.first(where: { $0.id == item.sessionID })
            if current?.token == item.token, current?.status == "unconfirmed" {
                server?.publish(PingviReplyResult(commandID: item.commandID, status: .uncertain, message: "Результат отправки неизвестен."))
                pending.removeValue(forKey: item.commandID)
            } else if current == nil || current?.token != item.token || current?.status == "working" || current?.status == "done" {
                server?.publish(PingviReplyResult(commandID: item.commandID, status: .accepted, message: "Агент продолжил работу."))
                pending.removeValue(forKey: item.commandID)
            }
        }
    }
}
