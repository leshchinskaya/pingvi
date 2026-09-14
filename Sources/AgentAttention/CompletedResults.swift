import SwiftUI

enum CompletedResults {
    static func sessions(in store: Store, workspace: String, includeViewed: Bool) -> [Session] {
        store.visible.filter {
            ($0.status == "done" || (includeViewed && $0.status == "viewed")) &&
            (workspace == "all" || (workspace == "ungrouped" ? store.workspaceID($0) == nil : store.workspaceID($0) == workspace))
        }.sorted { $0.updated == $1.updated ? $0.id < $1.id : $0.updated > $1.updated }
    }

    static func lastAnswer(in messages: [ChatMessage]) -> ChatMessage? {
        let after = messages.lastIndex { $0.role == "user" }
        return messages.dropFirst(after.map { $0 + 1 } ?? 0).last { $0.role == "assistant" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct CompletedResultsView: View {
    @ObservedObject var store: Store
    var workspace: String
    var previewHistories: [String: SearchHistory] = [:]
    @Environment(\.dismiss) private var dismiss
    @State private var includeViewed = false
    var sessions: [Session] { CompletedResults.sessions(in: store, workspace: workspace, includeViewed: includeViewed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Готовые результаты").font(.title3.weight(.semibold))
                    Text(workspace == "all" ? "Все пространства" : (workspace == "ungrouped" ? "Без пространства" : store.workspaces.first { $0.id == workspace }?.name ?? "Пространство"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Toggle("Показывать просмотренные", isOn: $includeViewed).toggleStyle(.checkbox)
                Spacer()
                if !sessions.isEmpty { Text("Результатов: \(sessions.count)").foregroundStyle(.secondary) }
            }.font(.caption).controlSize(.small)
            Divider()
            if sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.bubble").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.accent.opacity(0.6))
                    Text(includeViewed ? "Результатов пока нет" : "Новых результатов нет").font(.headline)
                    Text("Когда агент закончит ответ, он появится здесь.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(sessions) { session in CompletedResultCard(store: store, session: session, previewHistory: previewHistories[session.id]) }
                    }
                }
            }
        }.padding(24).frame(width: 680, height: 560, alignment: .topLeading).background(Palette.canvas)
    }
}

struct CompletedResultCard: View {
    @ObservedObject var store: Store
    var session: Session
    var previewHistory: SearchHistory? = nil
    @State private var history: SearchHistory?
    @State private var loading = true
    @State private var expanded = false
    @State private var error: String?
    @State private var revision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.title(session)).font(.headline)
                Spacer()
                if session.status == "viewed" { Label("Просмотрено", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary) }
            }
            Text(session.agent.capitalized + " · " + (session.project.isEmpty ? session.source : URL(fileURLWithPath: session.project).lastPathComponent))
                .font(.caption).foregroundStyle(.secondary)
            if loading { ProgressView("Загружаем ответ…").controlSize(.small) }
            else if let history, let answer = CompletedResults.lastAnswer(in: history.messages) {
                Text(answer.text).font(.callout).lineLimit(expanded ? nil : 6).textSelection(.enabled)
                Button(expanded ? "Свернуть" : "Развернуть ответ") { expanded.toggle() }.font(.caption)
                if history.partial { Text("История доступна частично").font(.caption2).foregroundStyle(.secondary) }
            } else {
                Text(error ?? "Ответ из истории недоступен. Откройте исходную сессию.").font(.callout).foregroundStyle(.secondary)
                Button("Повторить загрузку") { revision += 1 }.font(.caption)
            }
            HStack {
                Button("Открыть сессию") { store.open(session) }
                Spacer()
                if session.status == "done" {
                    Button("Просмотрено") { store.markViewed(session) }.disabled(loading)
                }
            }.font(.caption)
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .task(id: session.id + session.token + ":\(revision)") {
                if let previewHistory { history = previewHistory; loading = false; return }
                loading = true; error = nil; history = nil
                let result: Result<Data, Error> = await withCheckedContinuation { continuation in
                    Bridge.call(["action": "search-history", "session": ChatModel.payload(session)]) { continuation.resume(returning: $0) }
                }
                guard !Task.isCancelled else { return }
                do { history = try JSONDecoder().decode(SearchHistory.self, from: result.get()) }
                catch { self.error = "Не удалось загрузить ответ: " + error.localizedDescription }
                loading = false
            }
    }
}
