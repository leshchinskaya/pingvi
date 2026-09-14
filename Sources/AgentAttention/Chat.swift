import SwiftUI
import AppKit

struct ChatMessage: Decodable, Identifiable {
    var id: String
    var role: String
    var text: String
    var state: String
}
struct ChatHistory: Decodable {
    var messages: [ChatMessage]
    var partial: Bool
    var context: String
    var canSend: Bool
    var busy: Bool
    var reason: String
    var token: String
    var pending: Bool
}
struct ChatReceipt: Decodable { var state: String; var error: String? }
struct CreatedChat: Decodable { var session: Session }

final class ChatPreferences: ObservableObject {
    static let shared = ChatPreferences()
    struct Saved: Codable {
        var drafts: [String: String] = [:]
        var reading: [String: ChatReadingBookmark]? = [:]
        var replyBoundaries: [String: String]? = [:]
        var recentProjects: [String] = []
        var recentProjectsInitialized: Bool? = false
        var agent = "codex"
        var project = ""
        var firstMessage = ""
    }
    @Published var saved = Saved()
    private let file: URL
    var latestMessages: [String: String] = [:]
    init(storageDirectory: URL = Bridge.root) {
        file = storageDirectory.appendingPathComponent("chat-ui.json")
        if let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(Saved.self, from: data) { saved = value } }
    static func key(_ session: Session) -> String { session.target["pane"] ?? session.target["tty"] ?? session.id }
    func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(saved).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            persistenceError = nil
        } catch { /* Keep the in-memory draft; persistence failure is exposed below. */
            persistenceError = "Не удалось сохранить черновик на диск: " + error.localizedDescription
        }
    }
    func clearDrafts() throws {
        var clean = saved
        clean.drafts = [:]; clean.reading = [:]; clean.replyBoundaries = [:]; clean.firstMessage = ""; clean.project = ""; clean.recentProjects = []; clean.recentProjectsInitialized = true
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(clean).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        saved = clean; persistenceError = nil
    }
    @Published var persistenceError: String?
    func markReply(_ session: Session) {
        guard let id = latestMessages[Self.key(session)] else { return }
        if saved.replyBoundaries == nil { saved.replyBoundaries = [:] }
        saved.replyBoundaries?[Self.key(session)] = id
        save()
    }
    func draft(_ session: Session) -> String { saved.drafts[Self.key(session)] ?? "" }
    func setDraft(_ text: String, for session: Session) { saved.drafts[Self.key(session)] = text; save() }
}

final class ChatModel: ObservableObject {
    @Published var history: ChatHistory?
    @Published var error: String?
    @Published var sending = false
    @Published var loading = false
    static func payload(_ session: Session) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(session), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }
    func refresh(_ session: Session) async {
        guard !loading, UserDefaults.standard.bool(forKey: "chatEnabled") else { return }
        loading = true
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Bridge.call(["action": "chat-history", "session": Self.payload(session)]) { [weak self] result in
                defer { self?.loading = false; continuation.resume() }
                guard UserDefaults.standard.bool(forKey: "chatEnabled") else { return }
                do { self?.history = try JSONDecoder().decode(ChatHistory.self, from: result.get()); self?.error = nil }
                catch { self?.error = error.localizedDescription; self?.history?.canSend = false }
            }
        }
    }
    func send(_ session: Session, store: Store) {
        let preferences = ChatPreferences.shared
        let text = preferences.draft(session).trimmingCharacters(in: .whitespacesAndNewlines)
        guard UserDefaults.standard.bool(forKey: "chatEnabled"), history?.canSend == true, !sending, !text.isEmpty else { return }
        do { try AttachmentReference.validate(in: text) }
        catch { self.error = error.localizedDescription; return }
        sending = true
        Bridge.call(["action": "chat-send", "session": Self.payload(session), "text": text, "token": history!.token, "requestID": UUID().uuidString]) { [weak self] result in
            guard let self else { return }; self.sending = false
            do {
                let receipt = try JSONDecoder().decode(ChatReceipt.self, from: result.get())
                self.history?.canSend = false
                if receipt.state == "submitted" {
                    var contextSession = session
                    contextSession.detail = self.history?.context ?? session.detail
                    store.rememberAnsweredContext(contextSession)
                    preferences.markReply(session)
                    store.save()
                }
                if receipt.state == "submitted" && preferences.draft(session).trimmingCharacters(in: .whitespacesAndNewlines) == text { preferences.setDraft("", for: session) }
                self.error = receipt.error.map { "Результат отправки неизвестен. Проверьте сессию. " + $0 }
                store.poll()
            } catch { self.error = error.localizedDescription }
            Task { await self.refresh(session) }
        }
    }
    func acknowledge(_ message: ChatMessage, session: Session) {
        Bridge.call(["action": "chat-acknowledge", "session": Self.payload(session), "requestID": message.id]) { [weak self] result in
            do {
                _ = try result.get()
                let p = ChatPreferences.shared
                if p.draft(session).trimmingCharacters(in: .whitespacesAndNewlines) == message.text { p.setDraft("", for: session) }
            } catch { self?.error = error.localizedDescription }
            Task { await self?.refresh(session) }
        }
    }
}

struct SessionDetailView: View {
    @ObservedObject var store: Store
    var session: Session
    @AppStorage("chatEnabled") private var enabled = false
    var body: some View {
        if enabled { ChatView(store: store, session: session) }
        else { QuestionView(store: store, session: session) }
    }
}

struct ChatView: View {
    @ObservedObject var store: Store
    let session: Session
    @StateObject private var model = ChatModel()
    @ObservedObject private var preferences = ChatPreferences.shared
    @State private var showRequest = false
    @State private var visibleMessage: String?
    @State private var positioned = false
    @State private var readingReply: String?
    var messages: [ChatMessage] { model.history?.messages ?? [] }
    var replyBoundary: String? { preferences.saved.replyBoundaries?[ChatPreferences.key(session)] }
    var firstNew: String? { ChatReading.firstNew(in: messages, afterMessage: replyBoundary) }
    func rememberPosition() {
        guard positioned else { return }
        if preferences.saved.reading == nil { preferences.saved.reading = [:] }
        preferences.saved.reading?[ChatPreferences.key(session)] = ChatReadingBookmark(replyID: readingReply, visibleID: visibleMessage)
        preferences.save()
    }
    var requestPending: Bool { session.waiting && (!session.options.isEmpty || session.kind == "hook") }
    var draft: Binding<String> { Binding(get: { preferences.draft(session) }, set: { preferences.setDraft($0, for: session) }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.title(session)).font(.title3.weight(.semibold)).lineLimit(2)
                    Text(session.agent.capitalized + " · " + (session.project.isEmpty ? session.source : URL(fileURLWithPath: session.project).lastPathComponent)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.open(session) } label: { Image(systemName: "arrow.up.forward.app") }.help("Открыть исходную сессию")
            }
            if requestPending {
                Button { showRequest = true } label: {
                    HStack { Image(systemName: "hand.raised.fill"); Text("Агент ждёт подтверждения"); Spacer(); Image(systemName: "chevron.right") }
                        .font(.callout.weight(.medium)).padding(12).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            if model.history?.partial == true {
                Label("История неполная · доступен переход в исходную сессию", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if model.history == nil && model.error == nil { ProgressView("Загружаем переписку…").frame(maxWidth: .infinity).padding(30) }
                        if let h = model.history, !h.context.isEmpty {
                            RecentContextView(text: h.context, previous: store.local.answeredContext?[session.id], monospaced: true)
                        }
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                if message.id == firstNew { NewContentDivider() }
                                Text(message.role == "user" ? "Вы" : session.agent.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                FormattedMessage(text: message.text)
                                if message.state == "submitted" || message.state == "uncertain" {
                                    Text(message.state == "submitted" ? "Передано в сессию · ожидаем появления в истории" : "Результат отправки неизвестен").font(.caption2).foregroundStyle(.secondary)
                                    HStack {
                                        Button("Открыть сессию") { store.open(session) }
                                        Button("Проверила в сессии") { model.acknowledge(message, session: session) }
                                    }.controlSize(.small)
                                }
                                if message.state == "checked" { Text("Проверено вами в исходной сессии").font(.caption2).foregroundStyle(.secondary) }
                            }.padding(message.role == "user" ? 13 : 0)
                                .background(message.role == "user" ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 14)).id(message.id)
                        }
                        if model.history?.messages.isEmpty == true && model.history?.context.isEmpty == true {
                            Text("Сообщения появятся здесь. Можно написать первое сообщение, когда агент готов.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 24)
                        }
                        if model.history?.busy == true { Label("Агент пишет…", systemImage: "ellipsis.bubble").font(.caption).foregroundStyle(.secondary) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.scrollTargetLayout().padding(.vertical, 8)
                }.scrollPosition(id: $visibleMessage, anchor: .top)
                    .onChange(of: messages.map(\.id)) { _, _ in
                        if let last = messages.last { preferences.latestMessages[ChatPreferences.key(session)] = last.id }
                        guard !positioned, !messages.isEmpty else { return }
                        let bookmark = preferences.saved.reading?[ChatPreferences.key(session)]
                        let target = ChatReading.initialTarget(in: messages, bookmark: bookmark, afterMessage: replyBoundary)
                        readingReply = ChatReading.lastReply(in: messages, afterMessage: replyBoundary)
                        positioned = true
                        visibleMessage = target
                        if let target { reader.scrollTo(target, anchor: .top) }
                    }
                    .onChange(of: store.readingRequest) { _, _ in
                        guard !messages.isEmpty else { return }
                        readingReply = ChatReading.lastReply(in: messages, afterMessage: replyBoundary)
                        if let target = firstNew ?? messages.last?.id { reader.scrollTo(target, anchor: .top) }
                    }
                HStack {
                    if let firstNew = firstNew {
                        Button("К новому после ответа") { reader.scrollTo(firstNew, anchor: .top) }
                    }
                    Spacer()
                    Button("К последним сообщениям") { reader.scrollTo("bottom", anchor: .bottom) }
                }.font(.caption)
            }
            if let error = model.error ?? preferences.persistenceError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            VStack(alignment: .leading, spacing: 8) {
                MessageComposer(placeholder: "Сообщение агенту…", text: draft,
                                canSend: model.history?.canSend == true && !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                sending: model.sending) {
                    model.send(session, store: store)
                }
                Text(model.history?.canSend == true ? "Enter — отправить · Shift+Enter — новая строка" : (model.history?.reason ?? "Проверяем готовность агента…")).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(12).surface(radius: 16)
        }.task(id: session.id + session.status + session.token) {
            while !Task.isCancelled {
                await model.refresh(session)
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }.sheet(isPresented: $showRequest) {
            VStack {
                HStack { Text("Запрос агента").font(.headline); Spacer(); Button("Закрыть") { showRequest = false } }
                QuestionView(store: store, session: store.local.sessions.first(where: { $0.id == session.id }) ?? session)
            }.padding(24).frame(width: 530, height: 620)
        }.onChange(of: requestPending) { _, waiting in if !waiting { showRequest = false } }
            .onDisappear { rememberPosition() }
    }
}

struct NewChatView: View {
    @ObservedObject var store: Store
    @ObservedObject private var preferences = ChatPreferences.shared
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var error: String?
    @State private var requestID = UUID().uuidString
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Новый диалог").font(.title2.weight(.semibold)); Spacer(); Button("Отмена") { dismiss() }.disabled(creating) }
            Text("Сессия откроется в herdr после отправки первого сообщения.").font(.callout).foregroundStyle(.secondary)
            Picker("Агент", selection: $preferences.saved.agent) { Text("Codex").tag("codex"); Text("Claude Code").tag("claude") }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 8) {
                Text("Проект").font(.headline)
                Text(preferences.saved.project.isEmpty ? "Выберите папку проекта" : preferences.saved.project).font(.callout).textSelection(.enabled)
                HStack {
                    Button("Выбрать папку…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url { preferences.saved.project = url.path; preferences.save() }
                    }
                    Menu("Недавние") { ForEach(preferences.saved.recentProjects, id: \.self) { path in Button(path) { preferences.saved.project = path; preferences.save() } } }.disabled(preferences.saved.recentProjects.isEmpty)
                }
            }
            TextField("Первая задача или сообщение", text: $preferences.saved.firstMessage, axis: .vertical).textFieldStyle(.plain).lineLimit(6...12).padding(14).surface(radius: 14)
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if creating { ProgressView().controlSize(.small); Text("Создаём диалог…").font(.caption) }
                Spacer()
                Button("Начать диалог") { create() }.buttonStyle(.borderedProminent).tint(Palette.action).keyboardShortcut(.return, modifiers: .command)
                    .disabled(creating || preferences.saved.project.isEmpty || preferences.saved.firstMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 540).interactiveDismissDisabled(creating)
            .onAppear {
                if preferences.saved.recentProjects.isEmpty && preferences.saved.recentProjectsInitialized != true {
                    preferences.saved.recentProjectsInitialized = true
                    preferences.saved.recentProjects = Array(Set(store.visible.map(\.project).filter { !$0.isEmpty })).sorted().prefix(10).map { $0 }
                    preferences.save()
                }
            }
            .onChange(of: preferences.saved.firstMessage) { _, _ in preferences.save() }
            .onChange(of: preferences.saved.agent) { _, _ in preferences.save() }
    }
    func create() {
        guard UserDefaults.standard.bool(forKey: "chatEnabled"), !creating else { return }
        creating = true; error = nil; preferences.save()
        Bridge.call(["action": "chat-create", "agent": preferences.saved.agent, "project": preferences.saved.project, "text": preferences.saved.firstMessage, "requestID": requestID]) { result in
            creating = false
            do {
                let response = try JSONDecoder().decode(CreatedChat.self, from: result.get())
                store.local.sessions.append(response.session); store.selected = response.session.id; store.save(); store.poll()
                preferences.saved.recentProjects.removeAll { $0 == response.session.project }
                preferences.saved.recentProjects.insert(response.session.project, at: 0)
                preferences.saved.recentProjects = Array(preferences.saved.recentProjects.prefix(10))
                preferences.saved.firstMessage = ""; preferences.save(); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
