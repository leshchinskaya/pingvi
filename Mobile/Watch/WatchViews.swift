import PingviLink
import SwiftUI

struct WatchQueueView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        NavigationStack {
            List {
                Label(store.connected ? "На связи" : "Нет связи", systemImage: store.connected ? "checkmark.circle.fill" : "wifi.slash")
                    .foregroundStyle(store.connected ? .green : .secondary)
                if store.questions.isEmpty {
                    Text("Никто не ждёт").foregroundStyle(.secondary)
                } else {
                    ForEach(store.questions) { question in
                        NavigationLink {
                            WatchQuestionView(question: question)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(question.title).font(.headline)
                                Text(question.question).font(.caption).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pingvi")
            .alert("Pingvi", isPresented: Binding(
                get: { store.message != nil },
                set: { if !$0 { store.message = nil } }
            )) {
                Button("OK") { store.message = nil }
            } message: { Text(store.message ?? "") }
        }
    }
}

struct WatchQuestionView: View {
    @EnvironmentObject private var store: WatchStore
    let question: PingviQuestion
    @State private var answer = ""

    var body: some View {
        List {
            Text(question.question)
            ForEach(question.options) { option in
                Button(option.label) { store.send(question: question, answer: option.replyValue) }
                    .disabled(!canReply)
            }
            TextField("Короткий ответ", text: $answer)
            Button("Отправить") {
                store.send(question: question, answer: answer.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .disabled(!canReply || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !question.fields.isEmpty {
                Text("Для этого вопроса откройте Pingvi на iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(question.title)
    }

    private var canReply: Bool {
        store.connected && question.canReply && question.state == .waiting && question.fields.isEmpty
    }
}
