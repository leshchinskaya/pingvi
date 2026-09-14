import AppKit
import SwiftUI

/// Render the actual data controls with fixture counts, without polling user sessions.
enum ReleasePreview {
    static func captureDashboard(to destination: URL) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .aqua)
        UserDefaults.standard.setVolatileDomain(["chatEnabled": false, "setupComplete": true], forName: UserDefaults.argumentDomain)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
        store.local.sessions = [question,
            session("demo-tests", "Проверка оформления заказа", "Paper Plane", "Codex", "working"),
            session("demo-api", "Документация API", "Atlas", "Claude Code", "working"),
            session("demo-theme", "Тёмная тема", "Aurora", "Codex", "done")]
        store.local.drafts = [question.token: ["layout": "Карточки"]]
        store.selected = question.id
        let view = NSHostingView(rootView: ContentView(store: store).frame(width: 1020, height: 680))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view; view.frame = NSRect(x: 0, y: 0, width: 1020, height: 680)
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
