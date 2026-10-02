import AppKit
import SwiftUI
import DuskCore

/// The Obsidian palette. No hue anywhere: the popover earns its look from the
/// thin, oversized numerals and the hairlines, the way a watch dial does.
enum Obsidian {
    static let ground = Color(red: 0.043, green: 0.043, blue: 0.047)     // #0B0B0C
    static let glow = Color(red: 0.137, green: 0.137, blue: 0.145)       // #232325
    static let ink = Color(red: 0.957, green: 0.957, blue: 0.949)        // #F4F4F2
    static let edge = Color.white.opacity(0.07)
    static let hair = Color.white.opacity(0.08)
    static let hairStrong = Color.white.opacity(0.12)
    static let tick = Color.white.opacity(0.22)
    static let tickLong = Color.white.opacity(0.55)
}

/// The popover that replaces the right-click menu. Layout C from the design:
/// a lit-dial hero over a body of controls that never moves between states.
public struct PopoverView: View {
    @ObservedObject var model: PopoverModel

    public init(model: PopoverModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            Hero(model: model)
            Controls(model: model)
        }
        .frame(width: 320)
        .foregroundStyle(Obsidian.ink)
        .background(Obsidian.ground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Obsidian.edge, lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Hero

struct Hero: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        VStack(spacing: 0) {
            StatusPill(model: model).padding(.bottom, 22)
            numerals
            Text(caption.uppercased())
                .font(.system(size: 10))
                .tracking(2.2)
                .opacity(0.45)
                .padding(.top, 10)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(dial)
        .overlay(alignment: .bottom) { Hairline() }
    }

    @ViewBuilder private var numerals: some View {
        switch model.phase {
        case .countingDown(let until):
            if model.isVisible {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Numerals(text: CountdownFormat.string(seconds: until.timeIntervalSince(context.date)))
                }
            } else {
                Numerals(text: CountdownFormat.string(seconds: until.timeIntervalSinceNow))
            }
        case .indefinite:
            Numerals(text: "∞", size: 72, weight: .thin)
        case .off:
            Numerals(text: "Off").opacity(0.32)
        case .paused:
            Numerals(text: "Paused").opacity(0.32)
        }
    }

    private var caption: String {
        switch model.phase {
        case .countingDown: return "Remaining"
        case .indefinite: return "Until turned off"
        case .off: return "Click the icon for \(model.clickMinutes) minutes"
        case .paused: return "Resumes when charging past \(AutoOffPolicy.resumeLevel(threshold: model.threshold))%"
        }
    }

    /// Lit from within only while something runs; cold otherwise.
    @ViewBuilder private var dial: some View {
        if model.isLive {
            RadialGradient(colors: [Obsidian.glow, Obsidian.ground],
                           center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: 190)
        } else {
            Obsidian.ground
        }
    }
}

struct Numerals: View {
    let text: String
    var size: CGFloat = 64
    var weight: Font.Weight = .ultraLight

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .monospacedDigit()
            .kerning(-1.2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // One height for every state, so the body below never shifts when
            // the state changes — ∞ is drawn larger than the digits.
            .frame(height: 76)
    }
}

struct StatusPill: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
            Text(label).font(.system(size: 12, weight: .medium))
            Spacer(minLength: 8)
            Text(detail).font(.system(size: 12)).monospacedDigit().opacity(0.55)
        }
        .padding(.leading, 8)
        .padding(.trailing, 13)
        .frame(height: 32)
        .background(Capsule().fill(Obsidian.ground))
        .overlay(Capsule().strokeBorder(Obsidian.hair, lineWidth: 1))
        .overlay {
            if model.isLive && model.isVisible { Sheen() }
        }
    }

    private var icon: NSImage {
        switch model.phase {
        case .off, .paused: return StatusIcon.image(active: false, timer: false)
        case .countingDown: return StatusIcon.image(active: true, timer: true)
        case .indefinite: return StatusIcon.image(active: true, timer: false)
        }
    }

    private var label: String {
        switch model.phase {
        case .off: return "Dusk is off"
        case .paused: return "Paused"
        case .countingDown, .indefinite: return "Keeping awake"
        }
    }

    private var detail: String {
        switch model.phase {
        case .off: return "Mac sleeps normally"
        case .paused: return "battery below \(model.threshold)%"
        case .indefinite: return "no time limit"
        case .countingDown(let until): return "sleeps at \(Self.clock.string(from: until))"
        }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

/// One faint highlight travelling the pill's hairline.
///
/// Capped at 30 fps, and only built while the popover is open: a perpetual
/// animation once loaded WindowServer hard enough to lag the whole Mac, and
/// the cost lands on WindowServer, not on Dusk, so the app's own CPU never
/// shows it.
struct Sheen: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) / 5
            Capsule().strokeBorder(
                AngularGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.8),
                    .init(color: Color.white.opacity(0.75), location: 0.92),
                    .init(color: .clear, location: 1),
                ], center: .center, angle: .degrees(turn * 360)),
                lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Controls

struct Controls: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Keep awake for").padding(.bottom, -4)
            Ruler(model: model)
            VStack(spacing: 0) {
                ToggleRow(title: "Low Power Mode", isOn: model.lowPower, enabled: true) { model.onSetLowPower($0) }
                ToggleRow(title: "Dim the Screen", isOn: model.dim, enabled: model.canDim) { model.onSetDim($0) }
            }
            .overlay(alignment: .bottom) { Hairline() }
            ThresholdSlider(model: model)
            Footer(model: model)
        }
        .padding(16)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10)).tracking(2).opacity(0.45)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Obsidian.hair).frame(height: 1) }
}

/// The duration ruler. Dragging moves the needle across the stops; letting go
/// commits the stop under the pointer. A plain click commits too.
struct Ruler: View {
    @ObservedObject var model: PopoverModel
    /// Keeps the end labels inside the panel.
    private let inset: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ForEach(0..<DurationScale.count, id: \.self) { index in
                    let long = DurationScale.labels.contains { $0.index == index }
                    Rectangle()
                        .fill(long ? Obsidian.tickLong : Obsidian.tick)
                        .frame(width: 1, height: long ? 14 : 7)
                        .position(x: x(of: index, in: width), y: long ? 21 : 24.5)
                }
                ForEach(DurationScale.labels, id: \.index) { label in
                    Text(label.text)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .opacity(0.5)
                        .position(x: x(of: label.index, in: width) + nudge(label.index), y: 38)
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(Obsidian.ink)
                    .frame(width: 2, height: 30)
                    .opacity(model.needleIsLive ? 1 : 0.35)
                    .position(x: x(of: model.needleStop, in: width), y: 13)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    model.draggingStop = DurationScale.nearestStop(toFraction: fraction(at: drag.location.x, in: width))
                }
                .onEnded { drag in
                    let stop = DurationScale.nearestStop(toFraction: fraction(at: drag.location.x, in: width))
                    model.onCommitStop(stop)
                    model.draggingStop = nil
                })
        }
        .frame(height: 44)
    }

    /// 4h and ∞ are neighbouring stops, a tick apart — too close for two
    /// centred labels. Each leans away from the other instead.
    private func nudge(_ index: Int) -> CGFloat {
        switch index {
        case DurationScale.lastIndex - 1: return -4
        case DurationScale.lastIndex: return 4
        default: return 0
        }
    }

    private func x(of stop: Int, in width: CGFloat) -> CGFloat {
        inset + CGFloat(DurationScale.fraction(forStop: stop)) * (width - inset * 2)
    }

    private func fraction(at x: CGFloat, in width: CGFloat) -> Double {
        Double((x - inset) / (width - inset * 2))
    }
}

struct ToggleRow: View {
    let title: String
    let isOn: Bool
    let enabled: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13.5))
            Spacer()
            Capsule()
                .fill(isOn ? Obsidian.ink : Color.white.opacity(0.14))
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(isOn ? Obsidian.ground : Obsidian.ink).frame(width: 16, height: 16).padding(2)
                }
                .animation(.easeOut(duration: 0.15), value: isOn)
        }
        .frame(height: 42)
        .contentShape(Rectangle())
        .onTapGesture { if enabled { set(!isOn) } }
        .opacity(enabled ? 1 : 0.35)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// The battery floor. Shows the live value while dragging and commits on
/// release — committing per step would re-run the battery policy, and a pmset
/// round-trip, for every pixel of travel.
struct ThresholdSlider: View {
    @ObservedObject var model: PopoverModel

    private var shown: Int { model.draggingThreshold ?? model.threshold }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Turn off below").font(.system(size: 13.5))
                Spacer()
                Text(shown == 0 ? "Off" : "\(shown)%").font(.system(size: 13)).monospacedDigit().opacity(0.7)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let x = width * CGFloat(ThresholdScale.fraction(of: shown))
                ZStack(alignment: .leading) {
                    Rectangle().fill(Obsidian.hairStrong).frame(height: 2)
                    Rectangle().fill(Obsidian.ink).frame(width: x, height: 2)
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Obsidian.ink)
                        .frame(width: 5, height: 18)
                        .shadow(color: Color.white.opacity(0.35), radius: 4)
                        .offset(x: x - 2.5)
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        model.draggingThreshold = ThresholdScale.value(atFraction: Double(drag.location.x / width))
                    }
                    .onEnded { drag in
                        model.onSetThreshold(ThresholdScale.value(atFraction: Double(drag.location.x / width)))
                        model.draggingThreshold = nil
                    })
            }
            .frame(height: 18)
        }
    }
}

struct Footer: View {
    @ObservedObject var model: PopoverModel

    var body: some View {
        Button(action: { model.onQuit() }) {
            HStack {
                Text("Quit Dusk")
                Spacer()
                Text("⌘Q")
            }
            .font(.system(size: 12))
            .opacity(0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("q", modifiers: .command)
        .padding(.top, 2)
    }
}
