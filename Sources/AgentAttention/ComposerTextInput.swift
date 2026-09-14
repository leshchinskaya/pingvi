import SwiftUI
import AppKit

/// A native editor keeps image paste and the standard Edit menu on the same responder path.
struct ComposerTextInput: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    var send: () -> Void
    var pasteImage: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = ComposerTextView()
        editor.isRichText = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.textColor = .labelColor
        editor.allowsUndo = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ComposerTextView else { return }
        if editor.string != text && !editor.hasMarkedText() {
            let selection = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
        editor.isEditable = isEnabled
        editor.sendMessage = isEnabled ? send : {}
        editor.pasteImage = pasteImage
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, let editor = nsView.documentView as? NSTextView,
              let container = editor.textContainer, let layout = editor.layoutManager else { return nil }
        container.containerSize = NSSize(width: max(1, width - 14), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: min(120, max(20, ceil(layout.usedRect(for: container).height) + 4)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextInput
        init(_ parent: ComposerTextInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

final class ComposerTextView: NSTextView {
    var sendMessage: (() -> Void)?
    var pasteImage: ((Data) -> Void)?

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), NSPasteboard.general.availableType(from: [.png, .tiff]) != nil {
            return isEditable
        }
        return super.validateUserInterfaceItem(item)
    }

    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        let clipboard = NSPasteboard.general
        if let type = clipboard.availableType(from: [.png, .tiff]), let data = clipboard.data(forType: type) {
            pasteImage?(data)
        } else { super.paste(sender) }
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76) && !hasMarkedText() {
            if event.modifierFlags.contains(.shift) { insertNewlineIgnoringFieldEditor(nil) }
            else { sendMessage?() }
        } else { super.keyDown(with: event) }
    }
}
