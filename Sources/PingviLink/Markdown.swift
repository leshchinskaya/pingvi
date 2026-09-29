import Foundation

/// Block-level structure of an agent answer. Inline syntax (bold, links, `code`) stays in
/// the text and is left to `AttributedString(markdown:)` on the rendering side.
public enum PingviMarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case listItem(marker: String, text: String, indent: Int)
    case quote(String)
    case code(language: String, text: String)
    case rule
}

public enum PingviMarkdown {
    public static func blocks(_ source: String) -> [PingviMarkdownBlock] {
        var blocks: [PingviMarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var table: [String] = []
        var fence: (marker: String, language: String, lines: [String])?

        func flushText() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
            if !table.isEmpty { blocks.append(.code(language: "", text: table.joined(separator: "\n"))); table = [] }
        }

        for rawLine in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if let open = fence {
                if trimmed.hasPrefix(open.marker) && trimmed.drop(while: { $0 == open.marker.first }).isEmpty {
                    blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
                    fence = nil
                } else {
                    fence?.lines.append(rawLine)
                }
                continue
            }

            if let marker = ["```", "~~~"].first(where: trimmed.hasPrefix) {
                flushText()
                fence = (marker, String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces), [])
                continue
            }

            if trimmed.isEmpty {
                flushText()
                continue
            }

            if trimmed.hasPrefix("|") {
                if table.isEmpty { flushText() }
                table.append(trimmed)
                continue
            } else if !table.isEmpty {
                flushText()
            }

            if let heading = heading(trimmed) {
                flushText()
                blocks.append(heading)
                continue
            }

            if isRule(trimmed) {
                flushText()
                blocks.append(.rule)
                continue
            }

            if trimmed.hasPrefix(">") {
                if !paragraph.isEmpty { flushText() }
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            } else if !quote.isEmpty {
                flushText()
            }

            if let item = listItem(rawLine) {
                flushText()
                blocks.append(item)
                continue
            }

            // A wrapped continuation line of the previous list item.
            if paragraph.isEmpty, rawLine.hasPrefix(" "), case .listItem(let marker, let text, let indent)? = blocks.last {
                blocks[blocks.count - 1] = .listItem(marker: marker, text: text + "\n" + trimmed, indent: indent)
                continue
            }

            paragraph.append(trimmed)
        }

        if let open = fence {
            // An unterminated fence (e.g. a truncated message) still renders as code.
            blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
        }
        flushText()
        return blocks
    }

    private static func heading(_ line: String) -> PingviMarkdownBlock? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes.count, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String) -> PingviMarkdownBlock? {
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
        let indent = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
        let body = line.dropFirst(leading.count)
        if let first = body.first, "-*+".contains(first), body.dropFirst().first == " " {
            let text = body.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("[ ] ") { return .listItem(marker: "☐", text: String(text.dropFirst(4)), indent: indent) }
            if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") { return .listItem(marker: "☑", text: String(text.dropFirst(4)), indent: indent) }
            return .listItem(marker: "•", text: text, indent: indent)
        }
        let digits = body.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let afterDigits = body.dropFirst(digits.count)
        guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")", afterDigits.dropFirst().first == " " else { return nil }
        return .listItem(marker: digits + ".", text: afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces), indent: indent)
    }
}
