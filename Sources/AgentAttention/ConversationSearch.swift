import SwiftUI

struct SearchHistory: Decodable {
    var messages: [ChatMessage]
    var partial: Bool
    var available: Bool
}

enum ConversationSearch {
    static func matches(_ messages: [ChatMessage], query: String) -> [ChatMessage] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return messages.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    static func highlighted(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        var remaining = text.startIndex..<text.endIndex
        while let range = text.range(of: query, options: [.caseInsensitive], range: remaining, locale: .current) {
            if let start = AttributedString.Index(range.lowerBound, within: result),
               let end = AttributedString.Index(range.upperBound, within: result) {
                result[start..<end].backgroundColor = .yellow.opacity(0.3)
            }
            remaining = range.upperBound..<text.endIndex
        }
        return result
    }

    static func snippet(_ text: String, query: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let range = flat.range(of: query, options: [.caseInsensitive], locale: .current) else { return String(flat.prefix(180)) }
        let start = flat.index(range.lowerBound, offsetBy: -55, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: 100, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }
}

private struct SearchSelection: Identifiable {
    var id = UUID()
    var session: Session
    var history: SearchHistory
    var messageID: String
    var query: String
}

struct ConversationSearchView: View {
    @ObservedObject var store: Store
    var sessions: [Session]
    var query: String
    @State private var histories: [String: SearchHistory] = [:]
    @State private var loading = true
    @State private var selection: SearchSelection?
    @State private var revision = 0

    private var sessionKey: String { sessions.map(\.id).sorted().joined(separator: "\n") + "\n\(revision)" }
    private var unavailable: Int { sessions.filter { histories[$0.id]?.available == false }.count }
    private var partial: Bool { sessions.contains { histories[$0.id]?.partial == true && histories[$0.id]?.available == true } }
    private var count: Int { sessions.reduce(0) { $0 + ConversationSearch.matches(histories[$1.id]?.messages ?? [], query: query).count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.vertical, 4)
            HStack {
                Text("Сообщения · \(count)").font(.caption.weight(.semibold))
                Spacer()
                if loading { ProgressView().controlSize(.mini).accessibilityLabel("Поиск в переписке") }
                else { Button { revision += 1 } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Обновить поиск в переписке") }
            }.foregroundStyle(.secondary)
            ForEach(sessions) { session in
                if let history = histories[session.id] {
                    let matches = ConversationSearch.matches(history.messages, query: query)
                    if !matches.isEmpty {
                        Text(store.title(session)).font(.caption.weight(.medium)).lineLimit(1)
                        Text(session.agent.capitalized + " · " + URL(fileURLWithPath: session.project).lastPathComponent)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        ForEach(matches) { message in
                            Button {
                                selection = SearchSelection(session: session, history: history, messageID: message.id, query: query)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.role == "user" ? "Вы" : session.agent.capitalized).font(.caption2).foregroundStyle(.secondary)
                                    Text(ConversationSearch.highlighted(ConversationSearch.snippet(message.text, query: query), query: query))
                                        .font(.caption).lineLimit(3).multilineTextAlignment(.leading)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                    .background(Palette.input, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).help("Открыть переписку на этом сообщении")
                        }
                    }
                }
            }
            if count == 0 { Text(loading ? "Ищем в доступной переписке…" : "Совпадений в доступной переписке нет").font(.caption).foregroundStyle(.secondary) }
            if unavailable > 0 { Text("История недоступна: \(unavailable) диалогов").font(.caption2).foregroundStyle(.secondary) }
            if partial { Text("Часть истории ограничена последними 200 сообщениями или 4 МБ журнала.").font(.caption2).foregroundStyle(.secondary) }
        }.task(id: sessionKey) {
            loading = true
            histories = [:]
            // One read at a time; changing the query reuses these in-memory histories.
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            for session in sessions {
                guard !Task.isCancelled else { return }
                let result: Result<Data, Error> = await withCheckedContinuation { continuation in
                    Bridge.call(["action": "search-history", "session": ChatModel.payload(session)]) { continuation.resume(returning: $0) }
                }
                guard !Task.isCancelled else { return }
                histories[session.id] = (try? JSONDecoder().decode(SearchHistory.self, from: result.get()))
                    ?? SearchHistory(messages: [], partial: true, available: false)
            }
            loading = false
        }.sheet(item: $selection) { item in
            SearchConversationView(store: store, session: item.session, history: item.history, messageID: item.messageID, query: item.query)
        }
    }
}

struct SearchConversationView: View {
    @ObservedObject var store: Store
    var session: Session
    var history: SearchHistory
    var messageID: String
    var query: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(store.title(session)).font(.headline).lineLimit(2)
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Найдено: «\(query)» · " + session.agent.capitalized).font(.caption).foregroundStyle(.secondary)
            if history.partial { Text("Показан доступный фрагмент истории").font(.caption).foregroundStyle(.secondary) }
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(history.messages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(message.role == "user" ? "Вы" : session.agent.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(ConversationSearch.highlighted(message.text, query: query)).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(message.id == messageID ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                                .id(message.id)
                        }
                    }
                }.onAppear { reader.scrollTo(messageID, anchor: .top) }
                HStack {
                    Button("К найденному сообщению") { reader.scrollTo(messageID, anchor: .top) }
                    Spacer()
                    Button("Открыть сессию") { store.open(session) }
                }.font(.caption)
            }
        }.padding(24).frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: 650)
            .background(Palette.canvas)
    }
}
