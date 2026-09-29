import Foundation

/// A message typed while the session could not accept it. It waits on the phone and is sent
/// as soon as the Mac reports the session ready, so the user never has to wait to write.
struct MobileQueuedChat: Codable, Equatable {
    var text: String
    let queuedAt: Date
}

enum MobileChatQueue {
    /// One queued message per session: later sends are appended as new paragraphs, never dropped.
    static func enqueue(_ text: String, into existing: MobileQueuedChat?, now: Date = Date()) -> MobileQueuedChat {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let existing, !existing.text.isEmpty else { return MobileQueuedChat(text: text, queuedAt: now) }
        return MobileQueuedChat(text: existing.text + "\n\n" + text, queuedAt: existing.queuedAt)
    }

    /// A message goes straight out only when nothing is waiting ahead of it and the session is ready.
    static func sendsImmediately(connected: Bool, canSend: Bool, sending: Bool, hasQueued: Bool) -> Bool {
        connected && canSend && !sending && !hasQueued
    }

    static func readyToDeliver(connected: Bool, canSend: Bool, sending: Bool) -> Bool {
        connected && canSend && !sending
    }
}
