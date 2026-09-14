import Foundation

/// Only hide text when an exact overlap proves that it was present before the reply.
struct ReadingContext {
    var earlier: String
    var new: String

    init(text: String, previous: String?) {
        earlier = ""; new = text
        guard let previous, !previous.isEmpty, !text.isEmpty else { return }
        if text.hasPrefix(previous) {
            earlier = previous
            new = String(text.dropFirst(previous.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        let oldLines = previous.components(separatedBy: "\n")
        let lines = text.components(separatedBy: "\n")
        let common = zip(oldLines, lines).prefix(while: { $0 == $1 }).count
        if common >= 2, lines.prefix(common).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count >= 2 {
            earlier = lines.prefix(common).joined(separator: "\n")
            new = lines.dropFirst(common).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
        let limit = min(oldLines.count, lines.count)
        guard limit >= 2 else { return }
        for count in stride(from: limit, through: 2, by: -1) {
            let prefix = Array(lines.prefix(count))
            if prefix == Array(oldLines.suffix(count)), prefix.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count >= 2 {
                earlier = prefix.joined(separator: "\n")
                new = lines.dropFirst(count).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
        }
    }
}

struct ChatReadingBookmark: Codable {
    var replyID: String?
    var visibleID: String?
}

enum ChatReading {
    static func lastReply(in messages: [ChatMessage], afterMessage: String? = nil) -> String? {
        let userIndex = messages.lastIndex(where: { $0.role == "user" && $0.state != "uncertain" })
        let boundaryIndex = messages.firstIndex(where: { $0.id == afterMessage })
        guard let index = [userIndex, boundaryIndex].compactMap({ $0 }).max() else { return nil }
        return messages[index].id
    }
    static func firstNew(in messages: [ChatMessage], afterMessage: String? = nil) -> String? {
        guard let reply = lastReply(in: messages, afterMessage: afterMessage), let index = messages.firstIndex(where: { $0.id == reply }) else { return nil }
        return messages.dropFirst(index + 1).first?.id
    }
    static func initialTarget(in messages: [ChatMessage], bookmark: ChatReadingBookmark?, afterMessage: String? = nil) -> String? {
        if bookmark?.replyID == lastReply(in: messages, afterMessage: afterMessage), let id = bookmark?.visibleID, messages.contains(where: { $0.id == id }) { return id }
        return firstNew(in: messages, afterMessage: afterMessage) ?? messages.last?.id
    }
}

import SwiftUI

struct NewContentDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().frame(height: 1)
            Text("Новое").font(.caption.weight(.semibold)).fixedSize()
            Rectangle().frame(height: 1)
        }.foregroundStyle(Palette.accent).padding(.vertical, 6).accessibilityAddTraits(.isHeader)
    }
}

struct RecentContextView: View {
    var text: String
    var previous: String?
    var monospaced = false
    var body: some View {
        let context = ReadingContext(text: text, previous: previous)
        VStack(alignment: .leading, spacing: 10) {
            if !context.earlier.isEmpty {
                DisclosureGroup("До вашего ответа") { content(context.earlier) }.font(.caption)
                if !context.new.isEmpty { NewContentDivider() }
            }
            if !context.new.isEmpty { content(context.new) }
        }
    }
    func content(_ text: String) -> some View {
        FormattedMessage(text: text, size: monospaced ? 11 : 14, monospaced: monospaced)
    }
}
