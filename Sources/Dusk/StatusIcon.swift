import AppKit

/// The menu bar glyph: the approved three-chip design — a rounded chip with a
/// laptop and a crescent moon on it, the same artwork as the app icon (see
/// design/reference-crops/).
///
///   off              dark chip, laptop drawn as an outline, moon solid
///   on               indigo chip, laptop filled white, moon knocked out of it
///   + countdown      either chip with a ring badge at the corner
///
/// The chip matters as much as the drawing on it. An earlier version put a
/// bare glyph in the menu bar with nothing behind it, and it read as a faint
/// smudge among neighbouring icons; a filled chip gives the icon enough mass
/// to be found at a glance, and the state then reads from its colour before
/// any of the detail inside it has to be resolved.
///
/// Everything is painted opaquely over the chip, so the moon and the hinge
/// notch are drawn in the chip's own colour rather than punched through the
/// alpha channel — the chip underneath is opaque, so there is nothing to see
/// through, and paint is simpler than a transparency layer. That also means
/// none of these are template images: they carry their own colour.
enum StatusIcon {
    private static let size = NSSize(width: 18, height: 18)
    /// Keeps the chip off the very edge of the status item, the way the
    /// system's own icons sit with a little air around them.
    private static let inset: CGFloat = 0.5
    private static let side = size.width - inset * 2
    private static let chipRect = CGRect(x: inset, y: inset, width: side, height: side)

    // Geometry measured off the approved reference and kept in its own
    // coordinates: chip percentages, y from the top. See design/proto.py.
    private static let chipRadius: CGFloat = 22
    private static let screenBox = (x0: 22.09, yTop: 25.21, x1: 77.51, yBottom: 63.33)
    private static let screenRadius: CGFloat = 4
    private static let baseBox = (x0: 14.31, yTop: 65.62, x1: 85.07, yBottom: 73.54)
    private static let baseRadius: CGFloat = 2.2
    private static let notch = (width: 11.0, height: 2.4)
    /// The moon is SF Symbols' own `moon.fill`, not a shape built here.
    ///
    /// Subtracting one circle from another is how the reference draws it, and
    /// fitting those two circles to the reference gives (50.42, 46.23, r 11.88)
    /// and (57.12, 41.57, r 10.02). At the size the laptop's screen leaves —
    /// 55% of an 18pt chip — that crescent is about 3 physical pixels across at
    /// its widest and tapers to nothing at the horns, so anti-aliasing ate it
    /// and it stopped reading as a moon. Thickening it far enough to survive
    /// turned it into a circle with a bite out of it instead: the shape has no
    /// size at which both its outline and its taper fit in these few pixels.
    ///
    /// Apple already solved this, because every SF Symbol is drawn to hold up
    /// at exactly these sizes. Borrowing `moon.fill` is the whole fix.
    ///
    /// The fallback keeps the hand-built crescent, so a system without the
    /// symbol still gets a moon rather than an empty screen.
    private static let moonSymbol = "moon.fill"
    /// Height of the moon as a share of the chip, and the symbol weight. Both
    /// picked from a sweep rendered at true 18pt and 36pt — the screen is only
    /// 38% of the chip tall, so this sits deliberately close to filling it.
    private static let moonHeight: CGFloat = 42
    private static let moonWeight: NSFont.Weight = .black
    private static let moon = (cx: 49.6, cy: 44.4, r: 17.4)
    private static let moonCut = (cx: 63.5, cy: 37.4, r: 13.4)
    /// A touch heavier than the reference's own 2.6: at 18pt a hairline
    /// outline anti-aliases into grey mush.
    private static let strokeWeight: CGFloat = 3.0
    private static let badge = (cx: 76.0, cy: 71.5, r: 13.5, ring: 4.7)

    private static let indigo = NSColor(srgbRed: 74.0 / 255, green: 58.0 / 255, blue: 250.0 / 255, alpha: 1)
    private static let graphite = NSColor(srgbRed: 28.0 / 255, green: 28.0 / 255, blue: 30.0 / 255, alpha: 1)

    /// All four glyphs are constant, and `refreshStatusItem` runs on every
    /// countdown tick for the whole life of a timer — a two-hour one asks for an
    /// image 480 times. Draw each one once.
    private static let activeTimerImage = draw(active: true, timer: true)
    private static let activeImage = draw(active: true, timer: false)
    private static let idleTimerImage = draw(active: false, timer: true)
    private static let idleImage = draw(active: false, timer: false)

    static func image(active: Bool, timer: Bool) -> NSImage {
        switch (active, timer) {
        case (true, true): return activeTimerImage
        case (true, false): return activeImage
        case (false, true): return idleTimerImage
        case (false, false): return idleImage
        }
    }

    // MARK: - Chip coordinates

    private static func scaled(_ percent: CGFloat) -> CGFloat { percent / 100 * side }
    private static func px(_ percent: CGFloat) -> CGFloat { inset + scaled(percent) }
    /// The reference measures y downwards; AppKit draws it upwards.
    private static func py(_ percentFromTop: CGFloat) -> CGFloat { inset + scaled(100 - percentFromTop) }

    private static func rect(_ box: (x0: Double, yTop: Double, x1: Double, yBottom: Double)) -> CGRect {
        CGRect(x: px(box.x0), y: py(box.yBottom),
               width: scaled(box.x1 - box.x0), height: scaled(box.yBottom - box.yTop))
    }

    /// `moon.fill` in a flat colour.
    ///
    /// Symbols arrive as templates, which draw in whatever tint the context
    /// carries; painting the colour and then clipping it to the symbol with
    /// `destinationIn` is what fixes it to the one wanted here. The drawing is
    /// deferred to composite time, so the symbol still rasterises at the
    /// device's own scale rather than being scaled up from a small bitmap.
    private static func moonImage(tinted color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 64, weight: moonWeight)
        guard let symbol = NSImage(systemSymbolName: moonSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        return NSImage(size: symbol.size, flipped: false) { bounds in
            color.set()
            bounds.fill(using: .sourceOver)
            symbol.draw(in: bounds, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
    }

    private static func circle(cx: Double, cy: Double, r: Double) -> CGRect {
        CGRect(x: px(cx - r), y: py(cy + r), width: scaled(r * 2), height: scaled(r * 2))
    }

    private static func rounded(_ rect: CGRect, corner: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }

    // MARK: - Drawing

    private static func draw(active: Bool, timer: Bool) -> NSImage {
        let chip = (active ? indigo : graphite).cgColor
        let white = NSColor.white.cgColor
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            ctx.addPath(rounded(chipRect, corner: scaled(chipRadius)))
            ctx.setFillColor(chip)
            ctx.fillPath()

            ctx.addPath(rounded(rect(screenBox), corner: scaled(screenRadius)))
            ctx.addPath(rounded(rect(baseBox), corner: scaled(baseRadius)))
            if active {
                ctx.setFillColor(white)
                ctx.fillPath()

                // the hinge notch, painted back over the base in the chip's colour
                let notchRect = CGRect(x: px(50 - notch.width / 2),
                                       y: py(baseBox.yTop + notch.height * 0.65),
                                       width: scaled(notch.width), height: scaled(notch.height))
                ctx.addPath(rounded(notchRect, corner: notchRect.height / 2))
                ctx.setFillColor(chip)
                ctx.fillPath()
            } else {
                ctx.setStrokeColor(white)
                ctx.setLineWidth(scaled(strokeWeight))
                ctx.strokePath()
            }

            // The moon reads against whatever it sits on: the chip's own colour
            // where the screen is filled white, white where the screen is left
            // dark.
            drawMoon(in: ctx, color: active ? indigo : .white)

            if timer {
                // A gap in the chip's colour first, so the ring reads as a badge
                // sitting on top of the laptop rather than merging into it.
                let gap = scaled(badge.ring * 0.5)
                let outer = circle(cx: badge.cx, cy: badge.cy, r: badge.r)
                ctx.addEllipse(in: outer.insetBy(dx: -gap, dy: -gap))
                ctx.setFillColor(chip)
                ctx.fillPath()

                ctx.addEllipse(in: outer)
                ctx.setStrokeColor(white)
                ctx.setLineWidth(scaled(badge.ring))
                ctx.strokePath()
            }

            return true
        }

        // These carry their own colour — the chip is the point, and template
        // rendering would flatten it to a single tint.
        image.isTemplate = false
        return image
    }

    /// Centres `moon.fill` on the laptop's screen, or the hand-built crescent
    /// when the symbol is unavailable.
    private static func drawMoon(in ctx: CGContext, color: NSColor) {
        guard let symbol = moonImage(tinted: color) else {
            ctx.addEllipse(in: circle(cx: moon.cx, cy: moon.cy, r: moon.r))
            ctx.addEllipse(in: circle(cx: moonCut.cx, cy: moonCut.cy, r: moonCut.r))
            ctx.setFillColor(color.cgColor)
            ctx.fillPath(using: .evenOdd)
            return
        }
        let height = scaled(moonHeight)
        let width = height * (symbol.size.width / symbol.size.height)
        let centre = CGPoint(x: px((screenBox.x0 + screenBox.x1) / 2),
                             y: py((screenBox.yTop + screenBox.yBottom) / 2))
        symbol.draw(in: CGRect(x: centre.x - width / 2, y: centre.y - height / 2,
                               width: width, height: height),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }
}
