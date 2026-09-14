import AppKit
import Combine

enum IconMood: String, CaseIterable, Identifiable {
    case ice = "Ice", night = "Night", aurora = "Aurora", orbit = "Orbit", classic = "Pingvi"
    var id: String { rawValue }
    var title: String {
        switch self { case .ice: return "Лёд"; case .night: return "Ночь"; case .aurora: return "Аврора"; case .orbit: return "Орбита"; case .classic: return "Классика" }
    }
    var caption: String {
        switch self { case .ice: return "Геометрия и ясность"; case .night: return "Графит и серебро"; case .aurora: return "Свет и стекло"; case .orbit: return "Движение и энергия"; case .classic: return "Первый пингвин" }
    }
    var url: URL? { Bundle.main.url(forResource: rawValue, withExtension: "png") }
    var image: NSImage { Brand.images[self]! }
}

final class IconAppearance: ObservableObject {
    static let shared = IconAppearance()
    @Published private(set) var selected: IconMood = .ice
    private var observation: NSKeyValueObservation?
    private var applied = false
    static func resolve(mode: String, manual: String?, light: String?, dark: String?, isDark: Bool) -> IconMood {
        if mode == "system" { return IconMood(rawValue: (isDark ? dark : light) ?? "") ?? (isDark ? .night : .ice) }
        return IconMood(rawValue: manual ?? "") ?? .ice
    }
    func start() {
        observation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }
    func refresh() {
        let d = UserDefaults.standard
        let mood = Self.resolve(mode: d.string(forKey: "iconMode") ?? "system", manual: d.string(forKey: "iconManual"), light: d.string(forKey: "iconLight"), dark: d.string(forKey: "iconDark"), isDark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        guard selected != mood || !applied else { return }
        applied = true
        selected = mood
        NSApp.applicationIconImage = mood.image
    }
}

enum Brand {
    static let name = "Pingvi"
    static let images: [IconMood: NSImage] = Dictionary(uniqueKeysWithValues: IconMood.allCases.map { mood in
        (mood, mood.url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(systemSymbolName: "bell.fill", accessibilityDescription: mood.title)!)
    })
    static var icon: NSImage { IconAppearance.shared.selected.image }
    // A dedicated monochrome mark, not a downscaled illustration: readable at menu-bar size.
    static var menuIcon: NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            NSColor.black.setFill()
            // Ice artwork: arched head, two tapered wings and a triangular beak.
            // The light chest is negative space, so macOS can tint the whole mark.
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: 2 + (x - 230) * 0.019, y: 1 + (1120 - y) * 0.0185)
            }
            let left = NSBezierPath()
            left.move(to: point(775, 202))
            left.curve(to: point(454, 337), controlPoint1: point(635, 78), controlPoint2: point(479, 215))
            left.curve(to: point(234, 814), controlPoint1: point(418, 520), controlPoint2: point(249, 667))
            left.curve(to: point(343, 1118), controlPoint1: point(211, 953), controlPoint2: point(287, 1073))
            left.curve(to: point(516, 634), controlPoint1: point(422, 954), controlPoint2: point(447, 785))
            left.curve(to: point(775, 202), controlPoint1: point(570, 432), controlPoint2: point(681, 313))
            left.close(); left.fill()

            let right = NSBezierPath()
            right.move(to: point(735, 333))
            right.curve(to: point(1019, 842), controlPoint1: point(790, 499), controlPoint2: point(996, 645))
            right.curve(to: point(909, 1118), controlPoint1: point(1045, 971), controlPoint2: point(976, 1065))
            right.curve(to: point(735, 333), controlPoint1: point(780, 806), controlPoint2: point(687, 578))
            right.close(); right.fill()

            let beak = NSBezierPath()
            beak.move(to: point(775, 202)); beak.line(to: point(875, 263))
            beak.line(to: point(735, 333)); beak.close(); beak.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pingvi — вопросы агентов"
        return image
    }
}
