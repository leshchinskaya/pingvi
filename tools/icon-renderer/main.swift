import AppKit

// Usage: render-icon input.png output.png pixel-size
let args = CommandLine.arguments
guard args.count == 4, let size = Int(args[3]), size > 0,
      let artwork = NSImage(contentsOfFile: args[1]),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size,
                                   pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Expected readable input.png, output.png and positive pixel-size")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let bounds = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.clear.setFill()
bounds.fill(using: .copy)
AppIconLayout.image(from: artwork, size: CGFloat(size)).draw(in: bounds)
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon")
}
try png.write(to: URL(fileURLWithPath: args[2]))
