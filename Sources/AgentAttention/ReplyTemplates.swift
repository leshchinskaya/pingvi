import SwiftUI

struct ReplyTemplate: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var text: String
}

final class ReplyTemplates: ObservableObject {
    static let shared = ReplyTemplates()
    @Published private(set) var items: [ReplyTemplate]
    @Published private(set) var error: String?
    private let file: URL
    static let defaults = [
        ReplyTemplate(title: "Крайние случаи", text: "Проверь крайние случаи и возможные ошибки. Опиши, что ещё нужно учесть."),
        ReplyTemplate(title: "Добавить тесты", text: "Добавь тесты для изменённого поведения и запусти подходящие проверки."),
        ReplyTemplate(title: "Показать изменения", text: "Покажи diff и кратко объясни, что изменилось и почему.")
    ]

    init(storageDirectory: URL = Bridge.root) {
        file = storageDirectory.appendingPathComponent("reply-templates.json")
        items = Self.defaults
        if FileManager.default.fileExists(atPath: file.path) {
            do { items = try JSONDecoder().decode([ReplyTemplate].self, from: Data(contentsOf: file)) }
            catch { items = []; self.error = "Не удалось прочитать шаблоны: " + error.localizedDescription }
        }
    }

    private func persist(_ items: [ReplyTemplate]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(items).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        self.items = items; error = nil
    }

    func save(id: String?, title: String, text: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !text.isEmpty else {
            throw NSError(domain: "Templates", code: 1, userInfo: [NSLocalizedDescriptionKey: "Заполните название и текст шаблона."])
        }
        var updated = items
        if let id, let index = updated.firstIndex(where: { $0.id == id }) {
            updated[index].title = title; updated[index].text = text
        } else { updated.append(ReplyTemplate(title: title, text: text)) }
        try persist(updated)
    }

    func delete(_ id: String) throws { try persist(items.filter { $0.id != id }) }

    static func inserting(_ template: String, into draft: String) -> String {
        draft.isEmpty ? template : draft + (draft.hasSuffix("\n") ? "" : "\n\n") + template
    }
}

struct ReplyTemplateSettings: View {
    @ObservedObject var templates: ReplyTemplates
    @Environment(\.dismiss) private var dismiss
    @State private var editing: String?
    @State private var title = ""
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Шаблоны ответов").font(.headline); Spacer(); Button("Готово") { dismiss() } }
            Text("Шаблон добавляется в черновик. Перед отправкой его можно изменить.").font(.caption).foregroundStyle(.secondary)
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Новый шаблон") { reset() }
                        ForEach(templates.items) { item in
                            Button { editing = item.id; title = item.title; text = item.text } label: {
                                Text(item.title).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                    .background(editing == item.id ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(minWidth: 140, idealWidth: 170, maxWidth: 200)
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Название", text: $title)
                    TextEditor(text: $text).font(.body).scrollContentBackground(.hidden).padding(8)
                        .background(Palette.input, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty { Text("Текст шаблона…").foregroundStyle(.tertiary).padding(12).allowsHitTesting(false) }
                        }.accessibilityLabel("Текст шаблона")
                    HStack {
                        if let editing {
                            Button("Удалить", role: .destructive) {
                                do { try templates.delete(editing); reset() }
                                catch { self.error = error.localizedDescription }
                            }
                        }
                        Spacer()
                        Button("Сохранить") {
                            do { try templates.save(id: editing, title: title, text: text); reset() }
                            catch { self.error = error.localizedDescription }
                        }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.padding(.leading, 12).frame(minWidth: 270)
            }
            if let error = error ?? templates.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(24).frame(width: 600, height: 400).background(Palette.canvas)
    }
    private func reset() { editing = nil; title = ""; text = ""; error = nil }
}
