import PingviLink
import SwiftUI
import UIKit

struct MobileToast: Identifiable, Equatable {
    enum Style: Equatable {
        case info
        case success
        case failure
    }

    let id = UUID()
    let text: String
    let style: Style
}

struct MobileReplyFailure: Equatable {
    let reply: PingviReply
    let message: String
}

struct MobileChatFailure: Equatable {
    let text: String
    let message: String
}

enum MobileHaptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

extension PingviSessionStatus {
    var symbol: String {
        switch self {
        case .waiting, .checking, .unconfirmed: return "hand.raised.fill"
        case .working: return "ellipsis.bubble.fill"
        case .done: return "checkmark.bubble.fill"
        case .viewed: return "checkmark.bubble"
        case .offline: return "wifi.slash"
        case .unknown: return "bubble.left.and.bubble.right.fill"
        }
    }

    var color: Color {
        switch self {
        case .waiting, .checking, .unconfirmed: return .orange
        case .working: return MobilePalette.accent
        case .done: return .green
        case .viewed, .offline: return .secondary
        case .unknown: return MobilePalette.deep
        }
    }
}

enum MobileSyncText {
    /// "обновлено 5 мин назад"; nil when the app has never received a snapshot.
    static func updated(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        if now.timeIntervalSince(date) < 60 { return String(localized: "обновлено только что") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return String(localized: "обновлено \(formatter.localizedString(for: date, relativeTo: now))")
    }
}

private struct MobileConnectionBanner: View {
    @EnvironmentObject private var model: MobileAppModel

    private var inProgress: Bool {
        model.state == .searching || model.state == .connecting
    }

    private var title: String {
        switch model.state {
        case .searching, .connecting: return model.state.description
        default: return String(localized: "Нет связи с Mac")
        }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 12) {
                if inProgress {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "wifi.slash").foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if let updated = MobileSyncText.updated(model.lastSyncAt, now: context.date) {
                        Text(updated).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if !inProgress {
                    Button("Повторить") { model.reconnect() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .mobileGlassCard(radius: 18)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct MobileConnectionBannerModifier: ViewModifier {
    @EnvironmentObject private var model: MobileAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.state != .connected {
                    MobileConnectionBanner()
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: model.state == .connected)
    }
}

private struct MobileToastOverlay: ViewModifier {
    @EnvironmentObject private var model: MobileAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    toastView(toast)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 76)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .task(id: toast.id) {
                            UIAccessibility.post(notification: .announcement, argument: toast.text)
                            try? await Task.sleep(for: .seconds(3))
                            model.dismissToast(toast.id)
                        }
                        .onTapGesture { model.dismissToast(toast.id) }
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: model.toast)
    }

    private func toastView(_ toast: MobileToast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(toast.style)).foregroundStyle(color(toast.style))
            Text(toast.text).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .mobileGlassCard(radius: 22)
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ style: MobileToast.Style) -> String {
        switch style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    private func color(_ style: MobileToast.Style) -> Color {
        switch style {
        case .info: return MobilePalette.accent
        case .success: return .green
        case .failure: return .orange
        }
    }
}

extension View {
    /// Shows a slim status banner under the navigation bar while the Mac is unreachable.
    func mobileConnectionBanner() -> some View { modifier(MobileConnectionBannerModifier()) }

    func mobileToastOverlay() -> some View { modifier(MobileToastOverlay()) }
}
