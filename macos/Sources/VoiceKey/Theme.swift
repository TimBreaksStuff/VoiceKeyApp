import AppKit

/// The main window's palette and type, straight from the design handoff.
///
/// The window is a fixed light surface (it forces `.aqua`), so these are literal
/// sRGB values rather than semantic system colours — the paper/ink relationship
/// is the design, not the system's idea of a control background.
enum Theme {

    // MARK: - Surfaces

    static let paper = srgb(0xFB, 0xF9, 0xF4)
    static let paperSunken = srgb(0xF8, 0xF5, 0xEC)
    static let chrome = srgb(0xF1, 0xEC, 0xE1)
    static let field = srgb(0xF6, 0xF2, 0xE8)
    static let strip = srgb(0xF4, 0xEF, 0xE3)

    // MARK: - Lines

    static let stripBorder = srgb(0xE4, 0xDC, 0xC9)
    static let border = srgb(0xE4, 0xDD, 0xCC)
    static let borderSoft = srgb(0xED, 0xE7, 0xD9)
    static let borderRow = srgb(0xEF, 0xEA, 0xDD)
    static let keycapEdge = srgb(0xDC, 0xD3, 0xBF)

    // MARK: - Text

    static let inkHover = srgb(0x33, 0x2F, 0x29)
    static let ink2 = srgb(0x3D, 0x39, 0x31)
    static let ink3 = srgb(0x51, 0x4C, 0x44)
    static let muted = srgb(0x6E, 0x68, 0x5D)
    static let muted2 = srgb(0x8C, 0x85, 0x77)
    static let muted3 = srgb(0x9A, 0x93, 0x84)
    static let muted4 = srgb(0xA8, 0xA1, 0x92)

    // MARK: - Local and ready

    static let green = srgb(0x4E, 0x7F, 0x62)
    static let greenInk = srgb(0x33, 0x60, 0x4A)
    static let greenBg = srgb(0xED, 0xF2, 0xEC)
    static let greenBorder = srgb(0xC4, 0xD4, 0xC6)
    static let greenMeta = srgb(0x6E, 0x91, 0x79)

    // MARK: - Listening, and anything that destroys

    static let clay = srgb(0x9A, 0x60, 0x45)
    static let clayHover = srgb(0x7E, 0x46, 0x30)
    static let clayBg = srgb(0xF6, 0xED, 0xE6)
    static let clayBorder = srgb(0xE0, 0xC8, 0xB6)

    // MARK: - Working: the model is busy

    static let workingBg = srgb(0xF1, 0xEE, 0xE3)
    static let workingBorder = srgb(0xDC, 0xD3, 0xBF)

    /// The one ink, at whatever strength the element calls for.
    static func ink(_ alpha: CGFloat = 1) -> NSColor {
        srgb(0x1B, 0x19, 0x17).withAlphaComponent(alpha)
    }

    private static func srgb(_ red: Int, _ green: Int, _ blue: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255, alpha: 1)
    }

    // MARK: - Type

    /// Display and reading text. New York, via the system serif design — the
    /// handoff's Newsreader in spirit, without bundling a font file.
    static func serif(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif),
              let serif = NSFont(descriptor: descriptor, size: size)
        else { return base }
        return serif
    }

    /// UI text: navigation, controls, buttons. The handoff's Instrument Sans role.
    static func sans(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Labels, timestamps, numerals-as-labels.
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Tabular figures, so ticking numbers and stacked timestamps do not jitter.
    static func tabular(_ font: NSFont) -> NSFont {
        let descriptor = font.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    // MARK: - Labels

    /// A non-editable label. `tracking` is in ems, as the design states it.
    static func label(_ text: String, font: NSFont, color: NSColor = ink(),
                      tracking: CGFloat = 0, lineHeight: CGFloat = 0,
                      alignment: NSTextAlignment = .natural) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.attributedStringValue = attributed(text, font: font, color: color,
                                                 tracking: tracking, lineHeight: lineHeight,
                                                 alignment: alignment)
        field.alignment = alignment
        field.allowsDefaultTighteningForTruncation = false
        return field
    }

    static func attributed(_ text: String, font: NSFont, color: NSColor = ink(),
                           tracking: CGFloat = 0, lineHeight: CGFloat = 0,
                           alignment: NSTextAlignment = .natural) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        if lineHeight != 0 { paragraph.lineHeightMultiple = lineHeight }
        attributes[.paragraphStyle] = paragraph

        let styled = NSMutableAttributedString(string: text, attributes: attributes)
        // Kern all but the last glyph: a trailing letter-space would leave the
        // text sitting short of its own frame, throwing right-aligned rows off.
        if tracking != 0, text.count > 1 {
            styled.addAttribute(.kern, value: tracking * font.pointSize,
                                range: NSRange(location: 0, length: styled.length - 1))
        }
        return styled
    }

    /// A mono section label: "LIBRARY", "THIS WEEK", "TODAY".
    static func sectionLabel(_ text: String, size: CGFloat = 10,
                             color: NSColor = muted3) -> NSTextField {
        label(text.uppercased(), font: mono(size), color: color, tracking: 0.14)
    }

    /// A 1pt rule. Horizontal by default; `vertical` fixes the width instead.
    static func rule(_ color: NSColor, thickness: CGFloat = 1, vertical: Bool = false) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        let anchor = vertical ? view.widthAnchor : view.heightAnchor
        anchor.constraint(equalToConstant: thickness).isActive = true
        return view
    }
}

/// A label that wraps to whatever width it is given — plain `NSTextField` needs
/// a `preferredMaxLayoutWidth` to compute its height, and that width is only
/// known once Auto Layout has placed it.
final class WrappingLabel: NSTextField {

    init(attributed: NSAttributedString) {
        super.init(frame: .zero)
        isEditable = false
        isBordered = false
        isSelectable = true
        drawsBackground = false
        cell?.wraps = true
        cell?.isScrollable = false
        maximumNumberOfLines = 0
        lineBreakMode = .byWordWrapping
        attributedStringValue = attributed
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        guard preferredMaxLayoutWidth != bounds.width else { return }
        preferredMaxLayoutWidth = bounds.width
        invalidateIntrinsicContentSize()
    }
}

/// Top-left origin, so stacked content reads down the page like the design does.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
