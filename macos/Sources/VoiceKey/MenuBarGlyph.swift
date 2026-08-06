import AppKit

/// The menu-bar glyph ("Keycap & rules"), drawn rather than shipped as PNGs —
/// the design is four rectangles, so vector drawing stays sharp at every scale
/// and keeps the bundle free of raster assets. Geometry is the handoff spec's,
/// in an 18×18 box with y growing downwards (SVG coordinates).
enum MenuBarGlyph {
    enum Variant { case idle, recording }

    private static let cached: [Variant: NSImage] = [
        .idle: draw(.idle),
        .recording: draw(.recording),
    ]

    static func image(_ variant: Variant) -> NSImage? { cached[variant] }

    private static func draw(_ variant: Variant) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let rules = NSBezierPath()
            rules.append(NSBezierPath(rect: NSRect(x: 4.5, y: 6.9, width: 9, height: 1.4)))
            rules.append(NSBezierPath(rect: NSRect(x: 6, y: 10.3, width: 6, height: 1.4)))
            NSColor.black.set()

            switch variant {
            case .idle:
                let key = NSBezierPath(roundedRect: NSRect(x: 1.3, y: 1.3, width: 15.4, height: 15.4),
                                       xRadius: 4, yRadius: 4)
                key.lineWidth = 1.6
                key.stroke()
                rules.fill()
            case .recording:
                // solid keycap with the rules knocked out
                let key = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: 17, height: 17),
                                       xRadius: 4, yRadius: 4)
                key.append(rules)
                key.windingRule = .evenOdd
                key.fill()
            }
            return true
        }
        // template: macOS handles light/dark and the highlighted menu-bar state
        image.isTemplate = true
        return image
    }
}
