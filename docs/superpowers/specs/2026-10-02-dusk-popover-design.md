# Dusk popover — design

Date: 2026-10-02 · Status: approved in conversation, build authorised

## Goal

Replace the right-click `NSMenu` with a custom popover that looks like an expensive
app: black and white only, impressive through restraint rather than colour. Dusk is
being sold, and the stock menu reads as generic.

Success means: every control the menu has today still works; the four states read
at a glance; nothing animates while the popover is closed (a perpetual animation once
loaded WindowServer hard enough to lag the whole Mac — see the `mac-no-xcode`
memory, landmine 4); and it survives being screenshotted for a store page.

## What stays the same

- Left click on the icon: on for 15 minutes / off. Unchanged.
- Right click (or control-click): opens the popover instead of the menu.
- Every behaviour behind the controls — `setIntent`, the riders, the battery policy,
  the countdown, the privilege prompt. The popover is a new face on the same calls.

## Approved look — "Obsidian", layout C

Chosen through the visual companion (mockups under `.superpowers/brainstorm/`,
not committed).

- Panel 320pt wide, corner radius 20, true black `#0B0B0C`, a 1px inner hairline
  `rgba(255,255,255,.07)`, deep drop shadow.
- **Hero** (top): a radial glow `#232325 → #0B0B0C` behind the numerals, like a lit
  watch dial; a hairline rule under it.
  - Status pill: 32pt capsule, hairline border, the Dusk icon at 16pt, label on the
    left, detail on the right at 55% opacity.
  - Numerals: SF Pro Display, weight ultralight, 64pt, tabular figures.
  - Caption: 10pt uppercase, letter-spacing .22em, 45% opacity.
- **Body**: `KEEP AWAKE FOR` label, the ruler, two toggle rows separated by
  hairlines, the battery slider, a quiet `Quit Dusk ⌘Q` footer.
- Toggles: off = 14% white track, white knob; on = white track, black knob.
- Slider: 2pt hairline track, white fill, **capsule knob** 5×18pt with a faint glow.
- Ink `#F4F4F2`. No colour anywhere.
- **Menu bar icon goes monochrome**: off = dark chip with a white outlined laptop
  (as now); on = warm-white chip `#F2F1EE` with an ink laptop `#0E0E10` and the moon
  knocked back out in the chip colour. Indigo is retired.

## States

| State | Pill | Numerals | Caption | Pill highlight |
|---|---|---|---|---|
| Off | icon(off) · "Dusk is off" · "Mac sleeps normally" | "Off", 32% opacity | "Click the icon for 15 minutes" | none; hero has no glow |
| Counting down | icon(on+ring) · "Keeping awake" · "sleeps at 7:54" | remaining, e.g. `12:00` / `1:05:00` | "Remaining" | travelling |
| Until turned off | icon(on) · "Keeping awake" · "no time limit" | `∞` | "Until turned off" | travelling |
| Paused for battery | icon(off) · "Paused" · "battery below 20%" | "Paused", 32% opacity | "Resumes when charging past 25%" | none; no glow |

The body never changes between states, so nothing shifts when the state does.

## Interactions

**Ruler.** 25 evenly spaced stops: 5–60 min in 5-minute steps (12), 75–240 min in
15-minute steps (12), then ∞. So 0–1 h takes the left half, where most choices are.
Labels sit at their true stops: 5m, 30m, 1h, 2h, 4h, ∞. One tick per stop; labelled
stops get the long tick. Dragging moves the needle and snaps to the nearest stop;
**releasing commits**: a time arms that countdown (turning Dusk on if it was off),
∞ keeps it on indefinitely. Committing closes the popover. A plain click on the
ruler commits at that point.

The needle rests at: the armed duration while counting down; ∞ while indefinite;
otherwise the last committed duration (persisted, default 15), drawn at 35% opacity.

**Toggles and slider** apply immediately and leave the popover open. The slider
commits on release, as the old one did — a threshold per pixel would re-run the
battery policy, and a pmset round-trip, on every step. `Dim the Screen` is disabled
when `controller.canDim` is false.

**Closing.** Click outside, Esc, or clicking the icon again (either button — a click
on the icon while open only closes; it does not also toggle Dusk).

**The screen goes back down when the popover closes.** Reaching the popover with
the screen at zero means pressing the brightness key first, which opens a peek. The
current code ends that peek inside each menu action (`takeScreenBack()` in
`menuKeepAwakeFor` and `applyRiders`). With a popover that stays open across a
toggle, doing it per action would black the screen out from under the open panel.
So it moves to one place: the popover's close. The per-action calls are removed.

**Modals.** The privilege prompt and pmset failure alerts must never appear behind,
or inside the tracking of, a floating panel. Anything that can raise one closes the
popover first, and the alert runs on the next pass of the run loop — the same rule
the menu already followed.

## Architecture

New and changed units, each with one job:

- `DuskCore/DurationScale.swift` — pure. The 25 stops; `fraction(forStop:)`,
  `nearestStop(toFraction:)`, `minutes(atStop:)` (nil for ∞), `stop(forMinutes:)`,
  and the labelled stops. No AppKit; tested.
- `DuskCore/CountdownFormat.swift` — pure. Seconds → `12:00`, `1:05:00`, `0:59`,
  rounding up so a running countdown never shows `0:00`. Tested.
- `DuskCore/AutoOffPolicy.swift` — gains `resumeLevel(threshold:hysteresis:)`, which
  `decide` now uses, so the "resumes past 25%" caption and the policy cannot drift.
- `Dusk/PopoverModel.swift` — `ObservableObject`. `@Published` phase, deadline,
  armed/last minutes, rider flags, `canDim`, threshold, battery-resume level,
  `isVisible`, live drag stop. Holds action closures the AppDelegate sets. No
  `@State` anywhere (the macro plugin is not in the command-line tools).
- `Dusk/PopoverView.swift` — SwiftUI, the Obsidian design above. Reads the model;
  calls its closures.
- `Dusk/DuskPanel.swift` — borderless, non-activating `NSPanel` hosting the view;
  can become key (for Esc) without activating the app; placed under the status item
  and clamped to the screen. Owns dismissal: resigning key, a global mouse-down
  monitor, Esc. Reports close to its owner.
- `Dusk/AppDelegate.swift` — `showMenu` becomes `togglePopover`; pushes state into
  the model wherever `refreshStatusItem` runs; implements the model's actions on the
  existing methods; calls `controller.takeScreenBack()` on close.
- `Dusk/StatusIcon.swift` — monochrome on-state.
- Removed: `SwitchMenuItemView.swift`, `ThresholdSliderView.swift`, `showMenu`,
  `keepAwakeSubmenuItem`, `autoOffSubmenuItem`, `menuKeepAwakeFor`, `activeMenu`,
  `durationOptions`.

## Performance

The pill highlight and the countdown are the only moving parts, and both exist only
while `isVisible` is true — the views are not built at all otherwise, so a closed
popover costs nothing. The highlight runs in a `TimelineView` capped at 30 fps; the
countdown in a 1 s periodic `TimelineView`. Verified by measuring WindowServer CPU
with the popover open versus closed.

## Testing

- `DuskCheck`: `DurationScale` (stop count, label positions, snapping either side of
  a boundary, clamping, ∞ at the end, minutes↔stop round-trip), `CountdownFormat`
  (`12:00`, `1:05:00`, `0:59`, round-up, never `0:00` while positive), and
  `AutoOffPolicy.resumeLevel` (20→25, 98→100) plus `decide` unchanged.
- Snapshots: render `PopoverView` in all four states to PNG with `ImageRenderer`,
  from the real view code, and inspect them.
- Live: build, install, open the popover with a real right-click, drag the ruler,
  toggle, Esc to close; confirm with `pmset` and the Dusk log, and screenshot the
  real panel.
- WindowServer CPU, popover open versus closed.

## Out of scope

A light variant, localisation, a settings window, onboarding, keyboard control of
the ruler.
