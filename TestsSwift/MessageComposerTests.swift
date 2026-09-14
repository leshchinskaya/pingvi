import AppKit
import SwiftUI
import XCTest
@testable import AgentAttention

final class MessageComposerTests: XCTestCase {
    func testPasteImageAttachesFileAndTextPasteStillWorks() throws {
        _ = NSApplication.shared
        let pasteboard = NSPasteboard.general
        let original = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            pasteboard.clearContents()
            let items = original.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(items)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var draft = "Draft"
        let view = NSHostingView(rootView: MessageComposer(placeholder: "Ответ", text: Binding(get: { draft }, set: { draft = $0 }), canSend: true, imageDirectory: dir) { XCTFail("Paste must not send") }.padding().frame(width: 450, height: 180))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(view).first { $0 is NSTextView || $0 is NSTextField })
        XCTAssertTrue(window.makeFirstResponder(editor))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        pasteboard.clearContents()
        pasteboard.setData(try XCTUnwrap(bitmap.tiffRepresentation), forType: .tiff)
        let pasteItem = NSMenuItem(title: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let nativeEditor = try XCTUnwrap(window.firstResponder as? ComposerTextView)
        XCTAssertTrue(nativeEditor.validateUserInterfaceItem(pasteItem), "The Edit menu must enable Paste for an image")
        XCTAssertTrue(NSApp.sendAction(#selector(NSText.paste(_:)), to: window.firstResponder, from: nil))
        let deadline = Date().addingTimeInterval(3)
        while !draft.contains(AttachmentReference.prefix) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(draft.contains(AttachmentReference.prefix), "Pasting TIFF into the real composer must attach an image")
        XCTAssertTrue(draft.hasPrefix("Draft"))
        XCTAssertNoThrow(try AttachmentReference.validate(in: draft))
        pasteboard.clearContents(); pasteboard.setString(" plain text", forType: .string)
        let textEditor = try XCTUnwrap(window.firstResponder as? NSTextView)
        textEditor.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(NSApp.sendAction(#selector(NSText.paste(_:)), to: window.firstResponder, from: nil))
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(draft.hasPrefix(" plain text"), "Ordinary paste must retain native text behavior")
        withExtendedLifetime(window) {}
    }

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
