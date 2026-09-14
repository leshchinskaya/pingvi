import SwiftUI

/// Opaque, appearance-aware colors keep the icy surfaces legible without transparency.
enum Palette {
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
                           green: CGFloat((rgb >> 8) & 0xff) / 255,
                           blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
        })
    }

    static let accent = adaptive(light: 0x0066D6, dark: 0x73B9FF)
    // Filled controls retain white-label contrast in both appearances.
    static let action = adaptive(light: 0x0066D6, dark: 0x0868CE)
    static let navy = adaptive(light: 0x143454, dark: 0xD9ECFF)
    static let canvas = adaptive(light: 0xF2F8FF, dark: 0x101D2D)
    static let sidebar = adaptive(light: 0xDCECFC, dark: 0x172D45)
    static let surface = adaptive(light: 0xFAFDFF, dark: 0x1C3046)
    static let input = adaptive(light: 0xCDE3F8, dark: 0x233C56)
    static let selection = adaptive(light: 0xBBDDFD, dark: 0x244D76)
    static let border = adaptive(light: 0xBCD4EB, dark: 0x3A5672)
}

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
    var body: some View {
        LinearGradient(colors: [Palette.sidebar, Palette.canvas, Palette.surface],
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
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.background(selected ? Palette.selection : Palette.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(contrast == .increased ? Color.primary.opacity(0.6) : (selected ? Palette.accent.opacity(0.65) : Palette.border), lineWidth: selected ? 1.5 : 1))
    }
}

extension View {
    func navigationGlass(radius: CGFloat = 22) -> some View { modifier(NavigationGlass(radius: radius)) }
    func surface(radius: CGFloat = 22, selected: Bool = false) -> some View { modifier(Surface(radius: radius, selected: selected)) }
    @ViewBuilder func actionStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent).tint(Palette.action) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent).tint(Palette.action) } else { buttonStyle(.bordered) }
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
            .buttonStyle(.plain).foregroundStyle(Palette.accent).background(hovering && !disabled ? Palette.input : .clear, in: Circle())
            .onHover { hovering = $0 }.disabled(disabled).opacity(disabled ? 0.4 : 1).help(title).accessibilityLabel(title)
    }
}
