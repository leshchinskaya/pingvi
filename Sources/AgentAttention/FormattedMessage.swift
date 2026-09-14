import SwiftUI

/// Block parsing stays separate from inline Markdown so code is always literal.
enum MessageBlock: Equatable {
    case prose(String)
    case code(String, diff: Bool)

    static func parse(_ text: String) -> [MessageBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MessageBlock] = []
        var pending: [String] = []
        var fence: Character?
        var fenceLength = 0
        var isDiff = false
        func flush() {
            guard !pending.isEmpty else { return }
            let value = pending.joined(separator: "\n")
            if fence == nil { blocks.append(contentsOf: terminalBlocks(value)) }
            else { blocks.append(.code(value, diff: isDiff)) }
            pending = []
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                let count = trimmed.prefix(while: { $0 == marker }).count
                if count >= fenceLength && trimmed.dropFirst(count).isEmpty {
                    flush(); fence = nil
                } else { pending.append(line) }
            } else if let marker = trimmed.first, marker == "`" || marker == "~",
                      trimmed.prefix(while: { $0 == marker }).count >= 3 {
                flush()
                fence = marker
                fenceLength = trimmed.prefix(while: { $0 == marker }).count
                let language = trimmed.dropFirst(fenceLength).trimmingCharacters(in: .whitespaces).lowercased()
                isDiff = ["diff", "patch"].contains(language)
            } else { pending.append(line) }
        }
        flush()
        return blocks
    }

    static func change(_ line: String) -> Int {
        if let numbered = numberedLine(line) { return numbered.change }
        // File headers are metadata, not changed source lines.
        if line.hasPrefix("+++ ") || line.hasPrefix("--- ") { return 0 }
        if line.hasPrefix("+") { return 1 }
        if line.hasPrefix("-") { return -1 }
        return 0
    }

    private static func numberedLine(_ line: String) -> (change: Int, contentColumn: Int)? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let rest = line.dropFirst(indent)
        let digits = rest.prefix(while: { $0.isASCII && $0.isNumber }).count
        guard digits > 0 else { return nil }
        let suffix = rest.dropFirst(digits)
        guard suffix.isEmpty || suffix.first == " " else { return nil }
        let spaces = suffix.prefix(while: { $0 == " " }).count
        let content = suffix.dropFirst(spaces)
        let sign = content.first
        let change = sign == "+" ? 1 : (sign == "-" || sign == "−" ? -1 : 0)
        return (change, indent + digits + spaces + (change == 0 ? 0 : 1))
    }

    /// Recognize terminal hunks, including soft-wrapped continuation rows, without
    /// treating ordinary Markdown lists or standalone numbered text as a diff.
    private static func terminalBlocks(_ text: String) -> [MessageBlock] {
        let lines = text.components(separatedBy: "\n")
        var result: [MessageBlock] = []
        var prose: [String] = []
        var index = 0
        while index < lines.count {
            guard numberedLine(lines[index]) != nil else {
                prose.append(lines[index]); index += 1; continue
            }
            let start = index
            var changed = false
            while index < lines.count {
                let line = lines[index]
                if let numbered = numberedLine(line) {
                    changed = changed || numbered.change != 0
                } else if line.trimmingCharacters(in: .whitespaces).isEmpty ||
                            !(line.hasPrefix(" ") || line.hasPrefix("\t")) ||
                            line.trimmingCharacters(in: .whitespaces).hasPrefix("└") {
                    break
                }
                index += 1
            }
            let candidate = Array(lines[start..<index])
            if changed {
                if !prose.isEmpty { result.append(.prose(prose.joined(separator: "\n"))); prose = [] }
                result.append(.code(candidate.joined(separator: "\n"), diff: true))
            } else { prose.append(contentsOf: candidate) }
        }
        if !prose.isEmpty { result.append(.prose(prose.joined(separator: "\n"))) }
        return result
    }

    static func changes(in code: String) -> [Int] {
        let lines = code.components(separatedBy: "\n")
        let numbered = lines.contains { (numberedLine($0)?.change ?? 0) != 0 }
        var previous = 0
        return lines.map { line in
            if numbered, let row = numberedLine(line) { previous = row.change }
            else if !numbered { previous = change(line) }
            else if line.isEmpty || !(line.hasPrefix(" ") || line.hasPrefix("\t")) { previous = 0 }
            return previous
        }
    }
}

struct FormattedMessage: View {
    let text: String
    var size: CGFloat = 14
    var monospaced = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MessageBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let value):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(value.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            proseLine(line)
                        }
                    }
                case .code(let value, let diff):
                    codeBlock(value, diff: diff)
                }
            }
        }
        .font(.system(size: size, design: monospaced ? .monospaced : .default))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { geometry in
            Color.clear.onAppear { availableWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { _, width in availableWidth = width }
        })
    }

    private func inline(_ value: String) -> Text {
        let attributed = (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
        return Text(attributed)
    }

    @ViewBuilder private func proseLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let heading = trimmed.prefix(while: { $0 == "#" }).count
        if heading > 0 && heading <= 6 && trimmed.dropFirst(heading).hasPrefix(" ") {
            inline(String(trimmed.dropFirst(heading + 1)))
                .font(.system(size: size + CGFloat(7 - heading), weight: .semibold))
                .padding(.top, 4).accessibilityAddTraits(.isHeader)
        } else if trimmed.hasPrefix("> ") || trimmed == ">" {
            HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(.secondary.opacity(0.4)).frame(width: 3)
                inline(String(trimmed.dropFirst(min(2, trimmed.count)))).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        } else if ["- ", "* ", "+ "].contains(where: { trimmed.hasPrefix($0) }) {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                inline(String(trimmed.dropFirst(2)))
            }.padding(.leading, CGFloat(line.prefix(while: { $0 == " " }).count) * 4)
        } else {
            inline(line.isEmpty ? " " : line)
        }
    }

    private func codeBlock(_ value: String, diff: Bool) -> some View {
        let changes = MessageBlock.changes(in: value)
        // The shared VStack width gives every background the longest line's width.
        return ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(value.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                    let change = diff ? changes[index] : 0
                    Text(verbatim: line.isEmpty ? " " : line)
                        .font(.system(size: size, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10).padding(.vertical, 2)
                        .frame(minWidth: availableWidth, maxWidth: .infinity, alignment: .leading)
                        .background(change == 0 ? Color.clear : (change > 0 ? Color.green : Color.red).opacity(colorScheme == .dark ? 0.25 : 0.14))
                }
            }.frame(minWidth: availableWidth, alignment: .leading)
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
