import AppKit
import SwiftUI
import XCTest
@testable import AgentAttention

final class MessageComposerTests: XCTestCase {
    func testAttachmentPickerIsAttachedToFloatingQuestionPanel() throws {
        _ = NSApplication.shared
        let parent = QuestionPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
                                   styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        parent.level = .floating
        parent.hidesOnDeactivate = false
        let view = NSHostingView(rootView: MessageComposer(placeholder: "Ответ", text: .constant(""), canSend: true) {})
        parent.contentView = view
        parent.makeKeyAndOrderFront(nil)
        defer { parent.orderOut(nil) }
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let inspected = expectation(description: "File picker presented")
        let timer = Timer(timeInterval: 0.5, repeats: false) { _ in
            let picker = NSApplication.shared.windows.compactMap { $0 as? NSOpenPanel }.first { $0.isVisible }
            XCTAssertNotNil(picker)
            XCTAssertTrue(picker?.sheetParent === parent, "File picker must belong to the floating card instead of opening behind it")
            picker?.cancel(nil)
            inspected.fulfill()
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
        AttachmentPicker.present(from: view.window) { _ in XCTFail("Cancel must not change draft") }
        wait(for: [inspected], timeout: 5)
        timer.invalidate()
    }

    func testEnterSendsAndShiftEnterInsertsNewline() throws {
        try checkKeyboard(canSend: true, sending: false)
    }
    func testEnterCannotSendWhenUnavailableOrAlreadySending() throws {
        try checkKeyboard(canSend: false, sending: false)
        try checkKeyboard(canSend: true, sending: true)
    }
    private func checkKeyboard(canSend: Bool, sending: Bool) throws {
        _ = NSApplication.shared
        var draft = "Ответ"
        var sent = 0
        let expectedSends = canSend && !sending ? 1 : 0
        let view = NSHostingView(rootView: MessageComposer(placeholder: "Ответ", text: Binding(get: { draft }, set: { draft = $0 }), canSend: canSend, sending: sending) { sent += 1 }.padding().frame(width: 400, height: 150))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(view).first { $0 is NSTextView || $0 is NSTextField })
        XCTAssertTrue(window.makeFirstResponder(editor))
        window.makeKey()
        func pressReturn(_ modifiers: NSEvent.ModifierFlags = []) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
            window.sendEvent(event)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        pressReturn()
        XCTAssertEqual(sent, expectedSends)
        XCTAssertEqual(draft, "Ответ")
        let textEditor = try XCTUnwrap(window.firstResponder as? NSTextView)
        textEditor.setSelectedRange(NSRange(location: 2, length: 0))
        pressReturn(.shift)
        XCTAssertEqual(sent, expectedSends)
        XCTAssertEqual(draft, "От\nвет")
        withExtendedLifetime(window) {}
    }
}
