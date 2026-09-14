import AppKit

/// The menu bar glyph: an open angle — a diagonal arm above a separate base line,
/// with the corner left unclosed. While an auto-off countdown is running the mark
/// draws inside a hollow ring.
///
/// The gap is the whole point of the mark, so every state draws the same two
/// strokes and only the colour changes: idle renders as a template image, which
/// lets macOS tint it to match the menu bar in either appearance, while the
/// coloured states are painted literally, which template rendering would strip —
/// hence the two paths.
enum StatusIcon {
    private static let size = NSSize(width: 18, height: 18)
    private static let center = CGPoint(x: 9, y: 9)

    private static let ringRadius: CGFloat = 8
    private static let ringWidth: CGFloat = 1.15

    /// Shrinks the mark about its own centre so it clears the ring's inner edge,
    /// and recentres it on the canvas — the mark alone sits a hair right of
    /// centre, which a ring around it would show up.
    private static let ringFit = CGAffineTransform(translationX: center.x, y: center.y)
        .scaledBy(x: 0.74, y: 0.74)
        .translatedBy(x: -9.1, y: -9.0)

    /// Cyan into violet, laid across the whole canvas so the mark and the ring
    /// read as one object rather than two tinted pieces.
    private static let luxe = NSGradient(
        starting: NSColor(srgbRed: 0.13, green: 0.83, blue: 0.93, alpha: 1),
        ending: NSColor(srgbRed: 0.66, green: 0.33, blue: 0.97, alpha: 1)
    )!

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

    private static func draw(active: Bool, timer: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let fit = timer ? ringFit : .identity
            let markWidth: CGFloat = timer ? 1.4 : 1.7

            // The arm's lower tip stops about a stroke-width above the base, and
            // the base runs on past where the arm ends. Closing that corner, or
            // squaring off the caps, turns the mark into an ordinary "∠".
            let mark = CGMutablePath()
            mark.move(to: CGPoint(x: 4.2, y: 6.1), transform: fit)
            mark.addLine(to: CGPoint(x: 12.6, y: 14.5), transform: fit)

            mark.move(to: CGPoint(x: 3.4, y: 3.5), transform: fit)
            mark.addLine(to: CGPoint(x: 14.8, y: 3.5), transform: fit)

            var strokes: [(path: CGPath, width: CGFloat)] = [(mark, markWidth)]
            if timer {
                let ring = CGMutablePath()
                ring.addEllipse(in: CGRect(
                    x: center.x - ringRadius, y: center.y - ringRadius,
                    width: ringRadius * 2, height: ringRadius * 2
                ))
                strokes.append((ring, ringWidth))
            }

            if active && timer {
                // A gradient can only be laid down as a fill, so the strokes are
                // converted to their outlines and used as the clip.
                ctx.saveGState()
                for stroke in strokes {
                    ctx.addPath(stroke.path.copy(
                        strokingWithWidth: stroke.width,
                        lineCap: .round, lineJoin: .round, miterLimit: 10
                    ))
                }
                ctx.clip()
                luxe.draw(in: rect, angle: 45)
                ctx.restoreGState()
            } else {
                ctx.setStrokeColor((active ? NSColor.systemOrange : .black).cgColor)
                ctx.setLineCap(.round)
                for stroke in strokes {
                    ctx.setLineWidth(stroke.width)
                    ctx.addPath(stroke.path)
                    ctx.strokePath()
                }
            }

            return true
        }

        // Only the uncoloured glyphs may be recoloured by the system.
        image.isTemplate = !active
        return image
    }
}
