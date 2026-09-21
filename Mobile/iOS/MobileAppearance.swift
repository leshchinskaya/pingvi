import SwiftUI
import UIKit

enum MobileTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Как в iOS"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum MobileIconMood: String, CaseIterable, Identifiable {
    case ice = "Ice"
    case night = "Night"
    case aurora = "Aurora"
    case orbit = "Orbit"
    case classic = "Classic"

    var id: String { rawValue }
    var alternateIconName: String? { self == .ice ? nil : rawValue }
    var previewName: String { "Icon" + rawValue }

    var title: String {
        switch self {
        case .ice: return "Лёд"
        case .night: return "Ночь"
        case .aurora: return "Аврора"
        case .orbit: return "Орбита"
        case .classic: return "Классика"
        }
    }

    var caption: String {
        switch self {
        case .ice: return "Геометрия и ясность"
        case .night: return "Графит и серебро"
        case .aurora: return "Свет и стекло"
        case .orbit: return "Движение и энергия"
        case .classic: return "Первый пингвин"
        }
    }

    static func resolve(alternateIconName: String?) -> MobileIconMood {
        guard let alternateIconName else { return .ice }
        return MobileIconMood(rawValue: alternateIconName) ?? .ice
    }
}

@MainActor
final class MobileAppearance: ObservableObject {
    static let shared = MobileAppearance()

    @Published private(set) var selectedIcon: MobileIconMood
    @Published var errorMessage: String?

    private init() {
        selectedIcon = MobileIconMood.resolve(alternateIconName: UIApplication.shared.alternateIconName)
    }

    func select(_ mood: MobileIconMood) {
        let application = UIApplication.shared
        guard application.supportsAlternateIcons else {
            errorMessage = "Эта версия iOS не поддерживает смену иконки."
            return
        }
        guard selectedIcon != mood else { return }

        application.setAlternateIconName(mood.alternateIconName) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.errorMessage = "Не удалось изменить иконку: \(error.localizedDescription)"
                } else {
                    self?.selectedIcon = mood
                }
            }
        }
    }
}

enum MobilePalette {
    static let accent = Color(red: 0.08, green: 0.45, blue: 0.93)
    static let glow = Color(red: 0.30, green: 0.72, blue: 1.0)
    static let deep = Color(red: 0.16, green: 0.24, blue: 0.50)
}

struct MobileAmbientBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            LinearGradient(
                colors: [MobilePalette.glow.opacity(0.20), .clear, MobilePalette.deep.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct MobileGlassCard: ViewModifier {
    var radius: CGFloat
    var selected: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency, contrast != .increased {
            content
                .glassEffect(selected ? .regular.tint(MobilePalette.accent.opacity(0.20)) : .regular,
                             in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(selected ? MobilePalette.accent : Color.primary.opacity(contrast == .increased ? 0.35 : 0.10),
                                      lineWidth: selected ? 2 : 1)
                }
        }
    }
}

extension View {
    func mobileGlassCard(radius: CGFloat = 24, selected: Bool = false) -> some View {
        modifier(MobileGlassCard(radius: radius, selected: selected))
    }

    @ViewBuilder
    func mobilePrimaryButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent).tint(MobilePalette.accent)
        } else {
            buttonStyle(.borderedProminent).tint(MobilePalette.accent)
        }
    }
}
