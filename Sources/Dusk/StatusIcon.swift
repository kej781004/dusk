import AppKit

/// The menu bar glyph: a bold crescent moon, on its own — no laptop frame.
///
/// The app icon is a laptop with a moon cut into its screen (see
/// design/reference-crops/), and the first cut of this glyph shrank that
/// same compound shape to 18pt. It looked fine zoomed in during review, but
/// at true, unzoomed menu-bar size the screen rect, base bar and a thin
/// crescent all competing for the same 18 physical pixels anti-aliased into
/// a grey smudge — confirmed against a real screenshot, not assumed. A bare,
/// much bolder crescent (proofed at true 18px in design/candidate_states.py)
/// reads clearly at that size. This is also precedent, not invention: macOS's
/// own Focus/Do Not Disturb glyph is a plain moon at exactly this scale.
///
/// The moon is a true hole, not a painted patch: the big circle and the
/// offset smaller one are both added to one CGPath and filled with the
/// even-odd rule, so the menu bar shows through the gap exactly the way it
/// shows through the counter of a letter "e". That is what makes
/// `isTemplate` rendering work correctly on the idle glyph — a painted patch
/// would fight the system tint.
enum StatusIcon {
    private static let size = NSSize(width: 18, height: 18)
    private static let center = CGPoint(x: 9, y: 9)

    // Bold on purpose — thin proportions matching the app-icon reference
    // disappear at this size. Proofed at true 18px before being ported here.
    private static let moonRadius: CGFloat = 6.6
    private static let cutRadius: CGFloat = 4.9
    private static let cutOffset = CGPoint(x: 3.4, y: -1.2)

    private static let ringRadius: CGFloat = 7.6
    private static let ringWidth: CGFloat = 1.15
    /// Shrinks the moon in place so it clears the ring; the moon is already
    /// centred on the canvas, so — unlike the old off-centre "∠" mark and the
    /// laptop shape before it — this scales about the same point the ring
    /// does, with no recentring needed.
    private static let timerScale: CGFloat = 0.72

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

    /// The crescent as one even-odd path: the big circle, minus an offset
    /// smaller one. `scale` shrinks it in place about the canvas centre for
    /// the timer ring; 1 otherwise.
    private static func crescent(scale: CGFloat) -> CGPath {
        let fit = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -center.x, y: -center.y)
        let path = CGMutablePath()
        path.addEllipse(in: circle(at: center, radius: moonRadius), transform: fit)
        path.addEllipse(in: circle(at: CGPoint(x: center.x + cutOffset.x, y: center.y + cutOffset.y),
                                   radius: cutRadius), transform: fit)
        return path
    }

    private static func circle(at c: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
    }

    private static func draw(active: Bool, timer: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            ctx.addPath(crescent(scale: timer ? timerScale : 1))
            ctx.setFillColor((active ? brand : .black).cgColor)
            ctx.fillPath(using: .evenOdd)

            if timer {
                ctx.addEllipse(in: circle(at: center, radius: ringRadius))
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
