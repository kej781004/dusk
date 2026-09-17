import AppKit
import DuskCore

/// The low-battery floor as a draggable track rather than a list of fixed
/// choices.
///
/// Everything is drawn by hand. AppKit does have `NSSlider`, but it cannot show
/// the stop dots and the numbers underneath, and — more to the point — a control
/// dropped into a menu item has to survive menu tracking, which runs its own
/// event loop. So this view takes the mouse down and then pumps events itself
/// until the button comes back up, the same way `NSSlider` does outside a menu.
/// Nothing calls `cancelTracking`, so the menu stays open for the whole drag.
@MainActor
final class ThresholdSliderView: NSView {
    private static let viewWidth: CGFloat = 250
    private static let viewHeight: CGFloat = 68

    /// Leaves room for the knob to reach either end without clipping, and for the
    /// outermost numbers to stay inside the menu.
    private static let sidePadding: CGFloat = 24
    private static let trackY: CGFloat = 38
    private static let trackThickness: CGFloat = 4
    private static let knobRadius: CGFloat = 7.5
    private static let dotY: CGFloat = 26
    private static let dotRadius: CGFloat = 1.1
    private static let captionY: CGFloat = 50
    private static let labelY: CGFloat = 7

    /// The band of the row a click may grab. Clicking the caption or the numbers
    /// should not fling the knob across the track.
    private static let grabTop: CGFloat = 48
    private static let grabBottom: CGFloat = 20

    /// Live while dragging; the caller only hears about it when the drag ends.
    private var value: Int
    private let onCommit: (Int) -> Void
    /// Set while the drag pump below owns the mouse, so the fallback in `mouseUp`
    /// does not commit the same gesture twice.
    private var pumpingDrag = false

    init(value: Int, onCommit: @escaping (Int) -> Void) {
        self.value = ThresholdScale.snap(value)
        self.onCommit = onCommit
        super.init(frame: NSRect(x: 0, y: 0, width: Self.viewWidth, height: Self.viewHeight))
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ThresholdSliderView is created in code only") }

    /// Wraps the view in the menu item that carries it.
    static func item(value: Int, onCommit: @escaping (Int) -> Void) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = ThresholdSliderView(value: value, onCommit: onCommit)
        return item
    }

    // MARK: - Geometry

    private var trackLeft: CGFloat { Self.sidePadding }
    private var trackRight: CGFloat { bounds.width - Self.sidePadding }
    private var trackSpan: CGFloat { max(trackRight - trackLeft, 1) }

    private func x(for value: Int) -> CGFloat {
        trackLeft + CGFloat(ThresholdScale.fraction(of: value)) * trackSpan
    }

    private func value(atX x: CGFloat) -> Int {
        ThresholdScale.value(atFraction: Double((x - trackLeft) / trackSpan))
    }

    // MARK: - Dragging

    /// Menu tracking does not deliver dragged events to a view item, so the drag
    /// is pumped here instead. Returning without seeing the mouse up would leave
    /// the menu's own loop holding a button-down it never sees released.
    override func mouseDown(with event: NSEvent) {
        guard let window, grabs(event) else { return }
        pumpingDrag = true
        var current: NSEvent? = event

        while let event = current {
            follow(event)
            if event.type == .leftMouseUp { break }
            current = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp])
        }

        onCommit(value)
        pumpingDrag = false
    }

    /// Belt and braces. A menu decides for itself which events reach a view item —
    /// the sibling switch rows are driven off `mouseUp` for that reason — so if the
    /// pump above never sees the mouse go down, a plain click still has to land.
    override func mouseUp(with event: NSEvent) {
        guard !pumpingDrag, grabs(event) else { return }
        follow(event)
        onCommit(value)
    }

    private func grabs(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        return point.y >= Self.grabBottom && point.y <= Self.grabTop
    }

    private func follow(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let snapped = value(atX: point.x)
        guard snapped != value else { return }
        value = snapped
        needsDisplay = true
        // The knob has to keep up with the pointer while the run loop is parked
        // inside the drag pump above.
        displayIfNeeded()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawCaption()
        drawTrack()
        drawStops()
        drawKnob()
        drawLabels()
    }

    private func drawCaption() {
        let text = NSMutableAttributedString()
        let plain: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ]

        if value == 0 {
            text.append(NSAttributedString(string: "Never turn off automatically", attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        } else {
            let emphasis: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
            text.append(NSAttributedString(string: "Turn off below ", attributes: plain))
            text.append(NSAttributedString(string: "\(value)%", attributes: emphasis))
        }

        text.draw(at: NSPoint(x: trackLeft, y: Self.captionY))
    }

    private func drawTrack() {
        let rect = NSRect(x: trackLeft,
                          y: Self.trackY - Self.trackThickness / 2,
                          width: trackSpan,
                          height: Self.trackThickness)
        let radius = Self.trackThickness / 2

        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        // Zero fills nothing: an empty track is the clearest way to show that the
        // feature is switched off.
        let filledWidth = x(for: value) - trackLeft
        guard filledWidth > 0 else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: filledWidth, height: rect.height),
                     xRadius: radius, yRadius: radius).fill()
    }

    private func drawStops() {
        NSColor.tertiaryLabelColor.setFill()
        for index in 0..<ThresholdScale.stopCount {
            let stop = ThresholdScale.minimum + index * ThresholdScale.step
            let center = x(for: stop)
            let rect = NSRect(x: center - Self.dotRadius,
                              y: Self.dotY - Self.dotRadius,
                              width: Self.dotRadius * 2,
                              height: Self.dotRadius * 2)
            NSBezierPath(ovalIn: rect).fill()
        }
    }

    private func drawKnob() {
        let center = x(for: value)
        let rect = NSRect(x: center - Self.knobRadius,
                          y: Self.trackY - Self.knobRadius,
                          width: Self.knobRadius * 2,
                          height: Self.knobRadius * 2)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSGraphicsContext.restoreGraphicsState()

        // A hairline keeps the knob from dissolving into a light menu background.
        NSColor.black.withAlphaComponent(0.12).setStroke()
        let outline = NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
        outline.lineWidth = 0.5
        outline.stroke()
    }

    private func drawLabels() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        for stop in ThresholdScale.labelledValues {
            let text = NSAttributedString(string: "\(stop)", attributes: attributes)
            let size = text.size()
            // Centred on the stop, then pulled back inside the view so the first
            // and last numbers are not clipped by the menu's edge.
            let centred = x(for: stop) - size.width / 2
            let clamped = min(max(centred, 2), bounds.width - size.width - 2)
            text.draw(at: NSPoint(x: clamped, y: Self.labelY))
        }
    }
}
