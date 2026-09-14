import AppKit

enum AppIconLayout {
    // Shared by the bundled icon and the runtime Dock icon.
    static let artworkScale: CGFloat = 0.88

    static func image(from artwork: NSImage, size: CGFloat = 512) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
            NSGraphicsContext.current?.imageInterpolation = .high
            let inset = size * (1 - artworkScale) / 2
            artwork.draw(in: bounds.insetBy(dx: inset, dy: inset),
                         from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}
