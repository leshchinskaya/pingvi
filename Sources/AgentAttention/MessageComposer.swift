import SwiftUI

struct MessageComposer: View {
    @State private var inputAnchor = NSView()
    var placeholder: String
    @Binding var text: String
    var canSend: Bool
    var sending = false
    var showsSend = true
    var send: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(2...7)
                .onKeyPress(.return, phases: .down) { key in
                    // Let input methods confirm composed text before interpreting Enter as send.
                    if (inputAnchor.window?.firstResponder as? NSTextView)?.hasMarkedText() == true { return .ignored }
                    if key.modifiers.contains(.shift) {
                        (inputAnchor.window?.firstResponder as? NSTextView)?.insertNewlineIgnoringFieldEditor(nil)
                        return .handled
                    }
                    if canSend && !sending { send() }
                    return .handled
                }
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
        }.background(ComposerInputAnchor(view: inputAnchor).frame(width: 0, height: 0))
    }
}

private struct ComposerInputAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
