import SwiftUI

struct SessionToolsView: View {
    @ObservedObject var store: Store
    var session: Session
    @State private var editingNote = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.note(session).isEmpty {
                Button { editingNote = true } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "note.text").foregroundStyle(Palette.accent)
                        Text(store.note(session)).font(.callout).lineLimit(2)
                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }.padding(.vertical, 6).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Открыть и изменить заметку")
                    .accessibilityLabel("Заметка: " + store.note(session))
            }
            HStack {
                SessionReadAction(store: store, session: session)
                Spacer()
                if store.note(session).isEmpty {
                    Button { editingNote = true } label: {
                        Label("Заметка", systemImage: "note.text")
                    }.help("Добавить личную заметку к диалогу")
                }
            }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
        }
            .sheet(isPresented: $editingNote) { SessionNoteEditor(store: store, session: session) }
    }
}

struct SessionNoteEditor: View {
    @ObservedObject var store: Store
    var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var error: String?

    init(store: Store, session: Session) {
        self.store = store; self.session = session
        _text = State(initialValue: store.note(session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Заметка · " + store.title(session)).font(.headline).lineLimit(2)
            Text("Только для вас. Заметка не отправляется агенту.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.body).scrollContentBackground(.hidden).padding(8)
                .background(Palette.input, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Заметка к диалогу")
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Очистить") { text = "" }.disabled(text.isEmpty)
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    do { try store.setNote(text, for: session); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
            }
        }.padding(24).frame(width: 480, height: 330).background(Palette.canvas)
    }
}
