import AppKit
import SwiftUI

/// Render the actual data controls with fixture counts, without polling user sessions.
enum ReleasePreview {
    static func captureDashboard(to destination: URL, floating: Bool = false, dark: Bool = false, approval: Bool = false, settings: Bool = false) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        UserDefaults.standard.setVolatileDomain(["chatEnabled": false, "setupComplete": true], forName: UserDefaults.argumentDomain)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(storageDirectory: directory, notificationsEnabled: false)
        let now = Date().timeIntervalSince1970
        func session(_ id: String, _ title: String, _ project: String, _ agent: String, _ status: String) -> Session {
            Session(id: id, title: title, project: project, agent: agent, source: "herdr", status: status, question: "", options: [], token: id, canReply: false, kind: "screen", updated: now, target: [:], detail: "", fields: [])
        }
        var question = session("demo-design", "Новый экран профиля", "Aurora", "Claude Code", "waiting")
        question.kind = "hook"; question.canReply = true
        question.question = "Как показывать активность пользователя?"
        question.fields = [QuestionField(id: "layout", label: "Выберите компоновку", options: [
            FieldOption(label: "Карточки", description: "Больше воздуха и акцент на главных событиях"),
            FieldOption(label: "Компактный список", description: "Больше событий на одном экране")
        ], multi: false)]
        if approval {
            question.title = "Гости"; question.project = "up-sushi-ba"; question.agent = "Codex"
            question.kind = "screen"; question.fields = []
            question.question = "• Edited reports/GUESTS_MERGE_SETTLEMENT_2026-09-14.md (+1 -1)\n" +
                Array(repeating: "  20\n  21 − `services/guest_merge_tracking.py`:\n    `c90a7aece4ed7d8a6ea077a3a3`\n  21 + `services/guest_merge_tracking.py`:\n    `cc481d52028b5987d6624fb2f0`", count: 4).joined(separator: "\n")
            question.options = [
                Choice(id: "y", label: "Yes, proceed (y)"),
                Choice(id: "a", label: "Yes, and don't ask again for commands that start with `git add reports/GUESTS_MERGE_SETTLEMENT_2026-09-14.md` (a)"),
                Choice(id: "esc", label: "No, and tell Codex what to do differently (esc)")
            ]
        }
        store.local.sessions = [question,
            session("demo-tests", "Проверка оформления заказа", "Paper Plane", "Codex", "working"),
            session("demo-api", "Документация API", "Atlas", "Claude Code", "working"),
            session("demo-theme", "Тёмная тема", "Aurora", "Codex", "done")]
        store.local.drafts = [question.token: ["layout": "Карточки"]]
        store.selected = question.id
        let size = NSSize(width: floating ? 1120 : 1020, height: floating ? 760 : 680)
        let searchMessages = (0..<30).map {
            ChatMessage(id: "earlier-\($0)", role: "assistant", text: "Предыдущее обсуждение \($0).\nПроверены требования и сценарии обновления профиля.", state: "received")
        } + [
            ChatMessage(id: "search-match", role: "assistant", text: "Миграция профилей находится в db/profile.sql.\nПеред обновлением нужно проверить перенос настроек уведомлений.", state: "received"),
            ChatMessage(id: "search-followup", role: "user", text: "Добавь проверку сохранения настроек после обновления.", state: "received")
        ]
        let content = CommandLine.arguments.contains("--preview-search")
            ? AnyView(SearchConversationView(store: store, session: question,
                history: SearchHistory(messages: searchMessages, partial: false, available: true), messageID: "search-match", query: "миграция"))
            : settings ? AnyView(SettingsView(store: store, preview: true)) : floating
            ? AnyView(FloatingPreviewScene(store: store, id: question.id))
            : AnyView(ContentView(store: store))
        let view = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view; view.frame = NSRect(origin: .zero, size: size)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain: "Preview", code: 1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Preview", code: 2) }
        try data.write(to: destination)
        withExtendedLifetime(window) {}
    }

    static func captureData(to destination: URL) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = Store(storageDirectory: directory, notificationsEnabled: false)
        let view = NSHostingView(rootView: VStack(alignment: .leading, spacing: 0) {
            Text("Данные — Pingvi").font(.title.bold()).padding(24)
            Form { DataSettings(store: store, preview: true) }.formStyle(.grouped)
        }.frame(width: 760, height: 680))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 760, height: 680)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain: "Preview", code: 1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Preview", code: 2) }
        try data.write(to: destination)
        withExtendedLifetime(window) {}
    }
}
