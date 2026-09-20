import AppKit

/// The menu bar glyph: a laptop with a crescent moon cut into its screen —
/// the same shape family as the app icon (see design/render_icon.py), just
/// redrawn at menu-bar scale rather than shrunk from the 1024px master,
/// which would read as a blurry smudge at 18pt.
///
/// The moon is a true hole, not a painted patch: the laptop body (screen +
/// base) and the crescent (a big circle minus an offset smaller one) are all
/// added as subpaths of one CGPath and filled with the even-odd rule, so the
/// menu bar shows through the moon exactly as it shows through the gaps
/// between letters in a font. That is what makes `isTemplate` rendering work
/// correctly on the idle glyph — a painted patch would fight the system tint.
enum StatusIcon {
    private static let size = NSSize(width: 18, height: 18)

    // Geometry lives in an 18x18, y-up local space (AppKit's own convention),
    // proofed against the approved reference at design/menubar-contact-sheet.png
    // before being ported here — see design/preview_menubar.py.
    private static let screenRect = CGRect(x: 3.6, y: 7.2, width: 10.7 - 3.6, height: 13.0 - 7.2)
    private static let screenRadius: CGFloat = 0.55
    private static let baseRect = CGRect(x: 2.6, y: 5.8, width: 11.7 - 2.6, height: 7.4 - 5.8)
    private static let baseRadius: CGFloat = 0.4
    private static let moonCenter = CGPoint(x: 6.4, y: 10.4)
    private static let moonRadius: CGFloat = 2.05
    private static let cutCenter = CGPoint(x: 7.4, y: 11.1)
    private static let cutRadius: CGFloat = 1.72

    private static let ringCenter = CGPoint(x: 9, y: 9)
    private static let ringRadius: CGFloat = 7.4
    private static let ringWidth: CGFloat = 1.1

    /// The glyph's own bounding-box centre — off-centre in the canvas, the
    /// laptop sits left and low of (9,9) — used to shrink the glyph in place
    /// for the timer ring, the way the old "∠" mark's `ringFit` did.
    private static let shapeCenter = CGPoint(x: 7.15, y: 9.4)
    private static let timerScale: CGFloat = 0.8
    private static var timerFit: CGAffineTransform {
        CGAffineTransform(a: timerScale, b: 0, c: 0, d: timerScale,
                          tx: shapeCenter.x * (1 - timerScale),
                          ty: shapeCenter.y * (1 - timerScale))
    }

    /// Sampled from the approved app-icon reference (design/reference-3icons.png)
    /// so the menu bar and the app icon read as the same brand.
    private static let brand = NSColor(srgbRed: 74.0/255, green: 58.0/255, blue: 250.0/255, alpha: 1)
    private static let brandRingTint = NSColor(srgbRed: 150.0/255, green: 140.0/255, blue: 255.0/255, alpha: 0.85)

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

    /// The laptop-minus-moon silhouette as one even-odd path. `fit` shrinks
    /// and recentres it in place for the timer ring; identity otherwise.
    private static func silhouette(fit: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.addPath(CGPath(roundedRect: screenRect, cornerWidth: screenRadius, cornerHeight: screenRadius, transform: nil), transform: fit)
        path.addPath(CGPath(roundedRect: baseRect, cornerWidth: baseRadius, cornerHeight: baseRadius, transform: nil), transform: fit)
        path.addPath(CGPath(ellipseIn: CGRect(x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius,
                                              width: moonRadius * 2, height: moonRadius * 2), transform: nil), transform: fit)
        path.addPath(CGPath(ellipseIn: CGRect(x: cutCenter.x - cutRadius, y: cutCenter.y - cutRadius,
                                              width: cutRadius * 2, height: cutRadius * 2), transform: nil), transform: fit)
        return path
    }

    private static func draw(active: Bool, timer: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let body = silhouette(fit: timer ? timerFit : .identity)
            ctx.addPath(body)
            ctx.setFillColor((active ? brand : .black).cgColor)
            ctx.fillPath(using: .evenOdd)

            if timer {
                let ring = CGPath(ellipseIn: CGRect(x: ringCenter.x - ringRadius, y: ringCenter.y - ringRadius,
                                                    width: ringRadius * 2, height: ringRadius * 2), transform: nil)
                ctx.addPath(ring)
                ctx.setStrokeColor((active ? brandRingTint : .black).cgColor)
                ctx.setLineWidth(ringWidth)
                ctx.strokePath()
            }

            return true
        }

        // Only the uncoloured glyphs may be recoloured by the system.
        image.isTemplate = !active
        return image
    }
}
