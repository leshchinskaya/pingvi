import SwiftUI

struct QuestionContext: Decodable {
    var user: String
    var assistant: String
    var partial: Bool
}

struct QuestionContextView: View {
    var session: Session
    @State private var context: QuestionContext?
    @State private var loadedKey: String?
    @State private var failed = false
    @State private var expanded = false

    private var requestKey: String { session.id + ":" + session.token }
    private var currentContext: QuestionContext? { loadedKey == requestKey ? context : nil }
    private var hasContext: Bool {
        guard let context = currentContext else { return false }
        return !context.user.isEmpty || !context.assistant.isEmpty
    }
    private var preview: String {
        guard let context = currentContext, hasContext else {
            if loadedKey != requestKey { return "Загрузка…" }
            return failed ? "Не удалось загрузить" : "История недоступна"
        }
        let text = context.user.isEmpty ? context.assistant : context.user
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                    Text("Контекст").fontWeight(.medium).fixedSize()
                    Text(preview).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if hasContext {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                }.font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!hasContext)
                .accessibilityLabel(hasContext ? (expanded ? "Свернуть контекст" : "Развернуть контекст") : "Контекст: " + preview)
                .accessibilityValue(hasContext ? preview : "")
                .help(hasContext ? "Последнее сообщение и текст агента перед вопросом" : "Подробности доступны в исходной сессии")
            if expanded, let context = currentContext, hasContext {
                VStack(alignment: .leading, spacing: 10) {
                if !context.user.isEmpty { excerpt("Ваше последнее сообщение", text: context.user) }
                if !context.assistant.isEmpty { excerpt("Агент перед вопросом", text: context.assistant) }
                if context.partial {
                    Text("Доступен только фрагмент истории").font(.caption2).foregroundStyle(.secondary)
                }
                }.padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(Palette.accent.opacity(0.25)).frame(width: 2) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .task(id: requestKey) {
                let key = requestKey
                expanded = false
                let result: Result<Data, Error> = await withCheckedContinuation { continuation in
                    Bridge.call(["action": "question-context", "session": ChatModel.payload(session)]) {
                        continuation.resume(returning: $0)
                    }
                }
                guard !Task.isCancelled else { return }
                do {
                    context = try JSONDecoder().decode(QuestionContext.self, from: result.get())
                    failed = false
                } catch { context = nil; failed = true }
                loadedKey = key
            }
    }

    private func excerpt(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(text).font(.callout)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
