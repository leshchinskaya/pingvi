import SwiftUI

struct MessageComposer: View {
    @State private var inputAnchor = NSView()
    @State private var attachmentError: String?
    @ObservedObject private var templates = ReplyTemplates.shared
    @State private var editingTemplates = false
    var placeholder: String
    @Binding var text: String
    var canSend: Bool
    var sending = false
    var showsSend = true
    var imageDirectory = ClipboardImage.directory
    var send: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .center, spacing: 10) {
            Button {
                AttachmentPicker.present(from: inputAnchor.window) { urls in
                    do { text = try AttachmentReference.adding(urls, to: text); attachmentError = nil }
                    catch { attachmentError = error.localizedDescription }
                }
            } label: { Image(systemName: "paperclip").font(.system(size: 16)).frame(width: 24, height: 24) }
                .buttonStyle(.plain).disabled(sending)
                .accessibilityLabel("Прикрепить файл или скриншот")
                .help("Прикрепить локальный файл или скриншот")
            Menu {
                ForEach(templates.items) { item in
                    Button(item.title) { text = ReplyTemplates.inserting(item.text, into: text) }
                }
                Divider()
                Button("Управлять шаблонами…") { editingTemplates = true }
            } label: { Image(systemName: "text.badge.plus").font(.system(size: 16)).frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(sending).help("Вставить шаблон ответа").accessibilityLabel("Шаблоны ответов")
            ComposerTextInput(text: $text, send: { if canSend && !sending { send() } }, pasteImage: pasteImage)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty { Text(placeholder).foregroundStyle(.tertiary).allowsHitTesting(false) }
                }.accessibilityLabel(placeholder)
            if showsSend {
                Button { if canSend && !sending { send() } } label: {
                    Image(systemName: sending ? "hourglass" : "paperplane.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent).tint(Palette.action)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend || sending)
                .accessibilityLabel(sending ? "Отправляем сообщение" : "Отправить сообщение")
                .help("Отправить · Enter. Новая строка · Shift+Enter")
            }
        }
        if text.contains(AttachmentReference.prefix) {
            Text("Файлы передаются агенту по локальным путям. Удалите строку, чтобы убрать вложение.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        if let attachmentError { Text(attachmentError).font(.caption).foregroundStyle(.red) }
        }.background(ComposerInputAnchor(view: inputAnchor).frame(width: 0, height: 0))
            .sheet(isPresented: $editingTemplates) { ReplyTemplateSettings(templates: templates) }
    }

    private func pasteImage(_ data: Data) {
        guard !sending else { return }
        do {
            let url = try ClipboardImage.save(data, directory: imageDirectory)
            text = try AttachmentReference.adding([url], to: text)
            attachmentError = nil
        } catch { attachmentError = error.localizedDescription }
    }
}

private struct ComposerInputAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

enum AttachmentPicker {
    static func present(from window: NSWindow?, completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Прикрепить"
        panel.message = "Агент получит пути к локальным файлам. Файлы должны оставаться доступны по этим путям."
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK { completion(panel.urls) }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}
