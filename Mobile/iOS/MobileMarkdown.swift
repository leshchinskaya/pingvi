import PingviLink
import SwiftUI
import UIKit

/// Renders an agent answer: block structure from `PingviMarkdown`, inline styling from `AttributedString`.
struct MobileMarkdownView: View {
    private let blocks: [PingviMarkdownBlock]

    init(_ text: String) {
        blocks = MobileMarkdownCache.blocks(for: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: PingviMarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.inline(text)).textSelection(.enabled)
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level <= 2 ? .title3.bold() : .headline)
                .padding(.top, 4)
                .accessibilityAddTraits(.isHeader)
        case .listItem(let marker, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 14, alignment: .trailing)
                Text(Self.inline(text)).textSelection(.enabled)
            }
            .padding(.leading, CGFloat(min(indent, 4)) * 14)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(.tertiary).frame(width: 3)
                Text(Self.inline(text)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let text):
            MobileCodeBlock(language: language, code: text)
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private enum MobileMarkdownCache {
    private final class Box { let blocks: [PingviMarkdownBlock]; init(_ blocks: [PingviMarkdownBlock]) { self.blocks = blocks } }
    nonisolated(unsafe) private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 300
        return cache
    }()

    static func blocks(for text: String) -> [PingviMarkdownBlock] {
        let key = text as NSString
        if let cached = cache.object(forKey: key) { return cached.blocks }
        let blocks = PingviMarkdown.blocks(text)
        cache.setObject(Box(blocks), forKey: key)
        return blocks
    }
}

private struct MobileCodeBlock: View {
    @EnvironmentObject private var model: MobileAppModel
    let language: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? String(localized: "Код") : language)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    MobileHaptics.success()
                    model.showToast(String(localized: "Код скопирован"), style: .success)
                } label: {
                    Label("Скопировать", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Скопировать код")
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            Divider()
            ScrollView(.horizontal) {
                Text(code)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
