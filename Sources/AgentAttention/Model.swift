import Foundation
import AppKit
import UserNotifications

struct Choice: Codable, Identifiable { var id: String; var label: String }
struct FieldOption: Codable { var label: String; var description: String? }
struct QuestionField: Codable, Identifiable { var id: String; var label: String; var options: [FieldOption]; var multi: Bool }
struct Session: Codable, Identifiable {
    var id: String; var title: String; var project: String; var agent: String; var source: String
    var status: String; var question: String; var options: [Choice]; var token: String; var canReply: Bool
    var kind: String; var updated: Double; var target: [String: String]; var detail: String; var fields: [QuestionField]
    var focusedPane: Bool?
    var atSource: Bool?
    var waiting: Bool { ["waiting", "checking", "unconfirmed"].contains(status) }
    var statusLabel: String {
        switch status { case "waiting": return "Нужен ответ"; case "working": return "Работает"
        case "done": return "Результат не просмотрен"; case "viewed": return "Просмотрено"
        case "offline": return "Нет связи"; case "unconfirmed": return "Доставка не подтверждена"
        case "checking": return "Ответ отправлен · проверяем"
        default: return "Ожидает задачу" }
    }
}
struct Snapshot: Decodable { var sessions: [Session]; var errors: [String]; var completeSources: Set<String>? }
struct Workspace: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
}

struct LocalState: Codable {
    var workspaces: [Workspace]? = []
    var workspaceAssignments: [String: String]? = [:]
    var sessions: [Session] = []; var names: [String: String] = [:]; var drafts: [String: [String: String]] = [:]
    var excluded: Set<String> = []; var excludedProjects: Set<String> = []; var seen: Set<String> = []
    var dismissed: Set<String> = []; var snoozes: [String: Double] = [:]; var arrival: [String: Double] = [:]
    var retired: Set<String> = []
    var uncertain: [String: String]? = [:]
    var deliveryStarted: [String: Double]? = [:]
    var comments: [String: [String: String]]? = [:]
    var answeredContext: [String: String]? = [:]
    var readQuestions: [String: String]? = [:]
    var notes: [String: String]? = [:]
}

final class Bridge {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AgentAttention")
    static var python: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Python/bin/python3").path }
    static var script: String { Bundle.main.resourceURL!.appendingPathComponent("bridge/bridge.py").path }
    static func call(_ payload: [String: Any], completion: @escaping (Result<Data, Error>) -> Void) {
        if Installation.needsMove(), ["install-hooks", "chat-create"].contains(payload["action"] as? String ?? "") {
            completion(.failure(NSError(domain: "Installation", code: 1, userInfo: [NSLocalizedDescriptionKey: Installation.message])))
            return
        }
        var request = payload
        request["herdrPath"] = UserDefaults.standard.string(forKey: "herdrPath") ?? ""
        request["claudePath"] = UserDefaults.standard.string(forKey: "claudePath") ?? ""
        request["codexPath"] = UserDefaults.standard.string(forKey: "codexPath") ?? ""
        let python = self.python
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try BridgeProcess.run(executable: python, arguments: ["-E", "-s", "-B", script], input: JSONSerialization.data(withJSONObject: request))
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let error = obj["error"] as? String {
                    throw NSError(domain: "Bridge", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
                }
                DispatchQueue.main.async { completion(.success(data)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
}

final class Store: ObservableObject {
    @Published var local = LocalState()
    @Published var selected: String? { didSet { if selected != oldValue { advanceAfterReply = [:] } } }
    @Published var readingRequest = UUID()
    @Published var errors: [String] = []
    @Published var message: String?
    @Published var polling = false
    var showSettings: (() -> Void)?
    @Published var submitting: Set<String> = []
    @Published var lastUpdate: Date?
    var showDashboard: (() -> Void)?
    var onChange: (() -> Void)?
    var showQuestion: ((String) -> Void)?
    var closeQuestion: (() -> Void)?
    private var timer: Timer?
    private let stateFile: URL
    private let notificationsEnabled: Bool
    private var started = false
    private var sent: [String: String] = [:]
    var advanceAfterReply: [String: String] = [:]
    private var replyContexts: [String: Session] = [:]
    var visible: [Session] {
        local.sessions.filter { !local.excluded.contains($0.id) && !local.excludedProjects.contains($0.project) && !local.retired.contains($0.id) }
            .sorted { a, b in
                func rank(_ s: Session) -> Int { needsAttention(s) ? 0 : (s.status == "working" ? 1 : (s.status == "offline" ? 2 : 3)) }
                if rank(a) != rank(b) { return rank(a) < rank(b) }
                let left = local.arrival[a.token] ?? a.updated, right = local.arrival[b.token] ?? b.updated
                return left == right ? a.id < b.id : left < right
            }
    }
    var pending: [Session] { visible.filter { needsAttention($0) } }
    func isRead(_ s: Session) -> Bool {
        s.status == "waiting" && local.readQuestions?[s.id] == s.token
    }
    func needsAttention(_ s: Session) -> Bool { s.waiting && !isRead(s) }
    func toggleRead(_ s: Session) {
        guard let current = local.sessions.first(where: { $0.id == s.id }) else { return }
        if current.status == "done" { markViewed(current); return }
        guard current.status == "waiting" else { return }
        if isRead(current) { local.readQuestions?.removeValue(forKey: current.id) }
        else {
            if local.readQuestions == nil { local.readQuestions = [:] }
            local.readQuestions?[current.id] = current.token
            local.snoozes.removeValue(forKey: current.token)
        }
        save()
    }
    var current: Session? { visible.first { $0.id == selected } }
    var aggregate: String {
        if !pending.isEmpty { return "waiting" }
        if visible.contains(where: { $0.status == "done" }) { return "done" }
        if visible.contains(where: { $0.status == "working" }) { return "working" }
        return "idle"
    }
    init(storageDirectory: URL = Bridge.root, notificationsEnabled: Bool = true) {
        self.stateFile = storageDirectory.appendingPathComponent("state.json")
        self.notificationsEnabled = notificationsEnabled
        UserDefaults.standard.register(defaults: ["dock": true, "menubar": true, "questionNotifications": true, "completionNotifications": true, "floating": false, "terminal": false])
        if let data = try? Data(contentsOf: stateFile), let saved = try? JSONDecoder().decode(LocalState.self, from: data) {
            local = saved
            sent = saved.uncertain ?? [:]
            for i in local.sessions.indices where local.sessions[i].status != "done" && local.sessions[i].status != "viewed" {
                local.sessions[i].status = "offline"; local.sessions[i].canReply = false
            }
        }
    }
    func start() { poll(); timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.poll() } }
    private func persist(_ state: LocalState) throws {
        try FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var disk = state
        for i in disk.sessions.indices where !disk.sessions[i].waiting { disk.sessions[i].detail = "" }
        try JSONEncoder().encode(disk).write(to: stateFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateFile.path)
    }
    func save() {
        local.uncertain = sent
        do { try persist(local) }
        catch { message = "Не удалось сохранить очередь: \(error.localizedDescription)" }
        onChange?()
    }
    func note(_ session: Session) -> String { local.notes?[session.id] ?? "" }
    func setNote(_ text: String, for session: Session) throws {
        var updated = local
        if updated.notes == nil { updated.notes = [:] }
        updated.notes?[session.id] = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        try persist(updated)
        local = updated
        onChange?()
    }
    func clearQuestionDrafts() throws {
        var clean = local
        clean.drafts = [:]; clean.comments = [:]; clean.answeredContext = [:]; clean.uncertain = sent
        try persist(clean)
        local = clean
        replyContexts = [:]
        onChange?()
    }
    var workspaces: [Workspace] { local.workspaces ?? [] }
    func workspaceID(_ session: Session) -> String? { local.workspaceAssignments?[session.id] }
    func saveWorkspace(id: String? = nil, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let id, let index = local.workspaces?.firstIndex(where: { $0.id == id }) {
            local.workspaces?[index].name = name
        } else {
            if local.workspaces == nil { local.workspaces = [] }
            local.workspaces?.append(Workspace(name: name))
        }
        save()
    }
    func assign(_ session: Session, to workspace: String?) {
        guard workspace == nil || workspaces.contains(where: { $0.id == workspace }) else { return }
        if local.workspaceAssignments == nil { local.workspaceAssignments = [:] }
        local.workspaceAssignments?[session.id] = workspace
        save()
    }
    func deleteWorkspace(_ id: String) {
        local.workspaces?.removeAll { $0.id == id }
        local.workspaceAssignments = local.workspaceAssignments?.filter { $0.value != id }
        save()
    }
    func title(_ s: Session) -> String { local.names[s.id] ?? s.title }
    func choose(_ s: Session) {
        selected = s.id
        readingRequest = UUID()
        markViewed(s)
    }
    func markViewed(_ s: Session) {
        guard let index = local.sessions.firstIndex(where: { $0.id == s.id }),
              local.sessions[index].status == "done" else { return }
        local.sessions[index].status = "viewed"
        local.seen.insert(s.id)
        save()
    }
    func nextQuestion() {
        let queue = pending.filter { $0.status == "waiting" }
        guard !queue.isEmpty else { return }
        if let index = queue.firstIndex(where: { $0.id == selected }) { selected = queue[(index + 1) % queue.count].id }
        else { selected = queue[0].id }
    }
    func poll() {
        guard !polling else { return }; polling = true
        Bridge.call(["action": "snapshot", "terminal": UserDefaults.standard.bool(forKey: "terminal")]) { [weak self] result in
            guard let self else { return }; self.polling = false
            do {
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: result.get())
                self.errors = snapshot.errors; self.lastUpdate = Date()
                if let heartbeat = try? JSONSerialization.data(withJSONObject: ["time": Date().timeIntervalSince1970]) {
                    try? heartbeat.write(to: Bridge.root.appendingPathComponent("app-heartbeat.json"), options: .atomic)
                }
                self.merge(snapshot.sessions, completeSources: snapshot.completeSources ?? [])
            } catch {
                self.errors = [error.localizedDescription]
                for i in self.local.sessions.indices where !["done", "viewed"].contains(self.local.sessions[i].status) {
                    self.local.sessions[i].status = "offline"; self.local.sessions[i].canReply = false
                }
                self.save()
            }
        }
    }
    func merge(_ incoming: [Session], completeSources: Set<String> = ["herdr", "Terminal", "Claude Code"]) {
        let old = Dictionary(uniqueKeysWithValues: local.sessions.map { ($0.id, $0) })
        var merged: [Session] = []
        var completedReply: String?
        for var s in incoming {
            let previous = old[s.id]
            if s.status != "waiting" || local.readQuestions?[s.id] != s.token {
                local.readQuestions?.removeValue(forKey: s.id)
            }
            if s.kind == "screen" && s.status == "idle" && previous?.status == "working" { s.status = "done" }
            if s.status == "idle", let previous, ["done", "viewed"].contains(previous.status) { s.status = previous.status }
            if s.status == "done" && local.seen.contains(s.id) && previous?.status != "working" { s.status = "viewed" }
            if s.status == "working" { local.seen.remove(s.id); local.retired.remove(s.id) }
            if s.waiting && !s.token.isEmpty {
                if local.arrival[s.token] == nil { local.arrival[s.token] = Date().timeIntervalSince1970 }
                if sent[s.id] == s.token {
                    let elapsed = Date().timeIntervalSince1970 - (local.deliveryStarted?[s.id] ?? 0)
                    s.status = elapsed < 15 ? "checking" : "unconfirmed"; s.canReply = false
                }
            }
            // The current source state supersedes a sent question once it is no longer
            // pending. This observes progress; it does not claim a delivery receipt.
            // Preserve the guard only while that exact question remains on screen.
            if let token = sent[s.id], s.status != "offline", s.status != "unconfirmed",
               (!s.waiting || s.token != token) {
                if let answered = replyContexts.removeValue(forKey: s.id) { rememberAnsweredContext(answered) }
                if advanceAfterReply[s.id] == token && selected == s.id { completedReply = s.id }
                advanceAfterReply.removeValue(forKey: s.id)
                sent.removeValue(forKey: s.id); local.drafts.removeValue(forKey: token)
                local.comments?.removeValue(forKey: token)
                local.deliveryStarted?.removeValue(forKey: s.id)
            }
            if s.status == "unconfirmed" { advanceAfterReply.removeValue(forKey: s.id) }
            merged.append(s)
        }
        let ids = Set(incoming.map(\.id))
        for var missing in local.sessions where !ids.contains(missing.id) {
            if completeSources.contains(missing.source) {
                local.seen.remove(missing.id); local.retired.remove(missing.id)
                local.readQuestions?.removeValue(forKey: missing.id)
                local.notes?.removeValue(forKey: missing.id)
                local.workspaceAssignments?.removeValue(forKey: missing.id)
                local.excluded.remove(missing.id); local.names.removeValue(forKey: missing.id)
                sent.removeValue(forKey: missing.id); local.deliveryStarted?.removeValue(forKey: missing.id)
                replyContexts.removeValue(forKey: missing.id)
                advanceAfterReply.removeValue(forKey: missing.id)
                local.answeredContext?.removeValue(forKey: missing.id)
                local.comments?.removeValue(forKey: missing.token)
                local.drafts.removeValue(forKey: missing.token); local.arrival.removeValue(forKey: missing.token)
                local.dismissed.remove(missing.token); local.snoozes.removeValue(forKey: missing.token)
                continue
            }
            if !["done", "viewed"].contains(missing.status) { missing.status = "offline"; missing.canReply = false }
            merged.append(missing)
        }
        local.sessions = merged
        if let completedReply, selected == completedReply {
            message = "Агент продолжил работу после ответа"
            nextQuestion()
        }
        if !visible.contains(where: { $0.id == selected }) { selected = visible.first?.id }
        for s in visible {
            let previous = old[s.id]
            if s.status == "waiting" && needsAttention(s) && previous?.token != s.token && !local.dismissed.contains(s.token) && !isVisibleAtSource(s) {
                if UserDefaults.standard.bool(forKey: "questionNotifications") { notify(s, body: s.question, kind: "question") }
                if UserDefaults.standard.bool(forKey: "floating") { showQuestion?(s.id) }
            }
            if started && s.status == "done" && previous?.status != "done" && previous?.status != "viewed" && UserDefaults.standard.bool(forKey: "completionNotifications") {
                notify(s, body: "Агент закончил ответ. Открыть результат.", kind: "done")
            }
            if let date = local.snoozes[s.token], date <= Date().timeIntervalSince1970, s.waiting {
                local.snoozes.removeValue(forKey: s.token); local.dismissed.remove(s.token)
                if UserDefaults.standard.bool(forKey: "floating") { showQuestion?(s.id) }
                if UserDefaults.standard.bool(forKey: "questionNotifications") { notify(s, body: s.question, kind: "reminder") }
            }
        }
        started = true; save()
    }
    func isVisibleAtSource(_ s: Session) -> Bool {
        s.atSource == true
    }
    func notify(_ s: Session, body: String, kind: String) {
        guard notificationsEnabled else { return }
        let c = UNMutableNotificationContent(); c.title = title(s); c.subtitle = s.agent + " · " + s.source
        c.body = String(body.prefix(240)); c.userInfo = ["session": s.id, "kind": kind]
        MessageNotifications.send(c, identifier: kind + ":" + s.id + ":" + s.token, conversation: s.id)
    }
    func testNotification() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { [weak self] granted, error in
            guard granted else {
                DispatchQueue.main.async { self?.message = error?.localizedDescription ?? "Разрешите уведомления Pingvi в настройках macOS → Уведомления." }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Pingvi на связи 🐧"
            content.body = "Я принесу сюда вопросы ваших агентов. Нажмите, чтобы открыть очередь."
            DispatchQueue.main.async {
                MessageNotifications.send(content, identifier: "pingvi-test", conversation: "pingvi-test") { error in
                    if let error { DispatchQueue.main.async { self?.message = "Уведомление: " + error.localizedDescription } }
                }
            }
        }
    }
    func dismiss(_ s: Session) { local.dismissed.insert(s.token); save(); closeQuestion?() }
    func snooze(_ s: Session, minutes: Double) {
        local.snoozes[s.token] = Date().timeIntervalSince1970 + minutes * 60; local.dismissed.insert(s.token); save(); closeQuestion?()
    }
    func draft(_ s: Session, field: String) -> String { local.drafts[s.token]?[field] ?? "" }
    func setDraft(_ s: Session, field: String, value: String) { local.drafts[s.token, default: [:]][field] = value; save() }
    func comment(_ s: Session, field: String) -> String { local.comments?[s.token]?[field] ?? "" }
    func separateLegacyComments(_ s: Session) {
        var changed = false
        for field in s.fields where !field.options.isEmpty {
            let value = draft(s, field: field.id)
            let choices = field.multi ? value.components(separatedBy: ", ") : [value]
            guard !value.isEmpty, !choices.allSatisfy({ choice in field.options.contains { $0.label == choice } }) else { continue }
            if local.comments == nil { local.comments = [:] }
            local.comments?[s.token, default: [:]][field.id] = [value, comment(s, field: field.id)].filter { !$0.isEmpty }.joined(separator: " — ")
            local.drafts[s.token]?[field.id] = ""
            changed = true
        }
        if changed { save() }
    }
    func setComment(_ s: Session, field: String, value: String) {
        if local.comments == nil { local.comments = [:] }
        local.comments?[s.token, default: [:]][field] = value
        save()
    }
    func answers(_ s: Session) -> [String: String] {
        Dictionary(uniqueKeysWithValues: s.fields.map { field in
            let selection = draft(s, field: field.id).trimmingCharacters(in: .whitespacesAndNewlines)
            let addition = comment(s, field: field.id).trimmingCharacters(in: .whitespacesAndNewlines)
            return (field.id, [selection, addition].filter { !$0.isEmpty }.joined(separator: " — "))
        })
    }
    func rememberAnsweredContext(_ s: Session) {
        guard s.kind == "screen" else { return }
        if local.answeredContext == nil { local.answeredContext = [:] }
        local.answeredContext?[s.id] = s.detail.isEmpty ? s.question : s.detail
    }
    func reply(_ s: Session, answer: String = "") {
        guard s.canReply, !submitting.contains(s.id), sent[s.id] != s.token else { return }
        do {
            try AttachmentReference.validate(in: answer)
            for value in answers(s).values { try AttachmentReference.validate(in: value) }
        } catch { message = error.localizedDescription; return }
        let shouldAdvance = selected == s.id
        guard let data = try? JSONEncoder().encode(s), let obj = try? JSONSerialization.jsonObject(with: data) else { return }
        submitting.insert(s.id)
        Bridge.call(["action": "reply", "session": obj, "answer": answer, "answers": answers(s)]) { [weak self] result in
            guard let self else { return }; self.submitting.remove(s.id)
            switch result {
            case .success:
                self.replyContexts[s.id] = s
                ChatPreferences.shared.markReply(s)
                if shouldAdvance && self.selected == s.id { self.advanceAfterReply[s.id] = s.token }
                self.sent[s.id] = s.token
                if self.local.deliveryStarted == nil { self.local.deliveryStarted = [:] }
                self.local.deliveryStarted?[s.id] = Date().timeIntervalSince1970
                if let i = self.local.sessions.firstIndex(where: { $0.id == s.id }) { self.local.sessions[i].status = "checking"; self.local.sessions[i].canReply = false }
                self.save(); self.poll()
            case .failure(let error):
                // A missing helper result cannot prove that no input reached the agent.
                if (error as NSError).domain == "Bridge", [2, 408].contains((error as NSError).code) {
                    self.sent[s.id] = s.token
                    if self.local.deliveryStarted == nil { self.local.deliveryStarted = [:] }
                    self.local.deliveryStarted?[s.id] = 0
                    if let i = self.local.sessions.firstIndex(where: { $0.id == s.id }) {
                        self.local.sessions[i].status = "unconfirmed"; self.local.sessions[i].canReply = false
                    }
                    self.save()
                }
                self.message = error.localizedDescription; self.poll()
            }
        }
    }
    func open(_ s: Session) {
        guard let data = try? JSONEncoder().encode(s), let obj = try? JSONSerialization.jsonObject(with: data) else { return }
        Bridge.call(["action": "focus", "session": obj]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.markViewed(s)
            case .failure(let error): self.message = error.localizedDescription
            }
        }
    }
    func exclude(_ s: Session, project: Bool = false) {
        if project && !s.project.isEmpty { local.excludedProjects.insert(s.project) } else { local.excluded.insert(s.id) }
        selected = visible.first?.id; save()
    }
    func retire(_ s: Session) { local.retired.insert(s.id); selected = visible.first?.id; save() }
    func clearUncertain(_ s: Session) {
        sent.removeValue(forKey: s.id)
        local.deliveryStarted?.removeValue(forKey: s.id)
        local.drafts.removeValue(forKey: s.token)
        local.comments?.removeValue(forKey: s.token)
        advanceAfterReply.removeValue(forKey: s.id)
        replyContexts.removeValue(forKey: s.id)
        if let i = local.sessions.firstIndex(where: { $0.id == s.id }) {
            local.sessions[i].status = "idle"; local.sessions[i].canReply = false
            local.sessions[i].question = ""; local.sessions[i].detail = ""
        }
        save(); poll()
    }
    func installHooks() {
        Bridge.call(["action": "install-hooks"]) { [weak self] result in
            switch result {
            case .success: self?.message = "Claude подключён. Перезапустите существующие сессии Claude, чтобы они загрузили интеграцию."
            case .failure(let e): self?.message = e.localizedDescription
            }
        }
    }
}
