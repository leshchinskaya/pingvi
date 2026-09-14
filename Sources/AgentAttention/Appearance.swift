import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Как в macOS"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
    static func saved(in defaults: UserDefaults = .standard) -> AppTheme {
        AppTheme(rawValue: defaults.string(forKey: "appTheme") ?? "") ?? .system
    }
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Shared materials for the dashboard, menu panel and question window.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: scheme == .dark
                       ? [Color(red: 0.08, green: 0.12, blue: 0.20), Color(red: 0.06, green: 0.08, blue: 0.13)]
                       : [Color(red: 0.95, green: 0.97, blue: 1), Color(red: 0.97, green: 0.98, blue: 1)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct NavigationGlass: ViewModifier {
    var radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.primary.opacity(0.25)))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
        }
    }
}

struct Surface: ViewModifier {
    var radius: CGFloat = 22
    var selected = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(selected ? Palette.accent.opacity(scheme == .dark ? 0.25 : 0.11) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(selected ? Palette.accent.opacity(0.55) : Color.primary.opacity(contrast == .increased ? 0.3 : 0.045), lineWidth: selected ? 1.5 : 1))
    }
}

extension View {
    func navigationGlass(radius: CGFloat = 22) -> some View { modifier(NavigationGlass(radius: radius)) }
    func surface(radius: CGFloat = 22, selected: Bool = false) -> some View { modifier(Surface(radius: radius, selected: selected)) }
    @ViewBuilder func actionStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

struct ToolbarAction: View {
    let symbol: String
    let title: String
    var disabled = false
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 30, height: 32) }
            .buttonStyle(.plain).background(hovering && !disabled ? Color.primary.opacity(0.08) : .clear, in: Circle())
            .onHover { hovering = $0 }.disabled(disabled).opacity(disabled ? 0.4 : 1).help(title).accessibilityLabel(title)
    }
}
