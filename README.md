# Dusk

A macOS menu bar app that **keeps your Mac awake with the lid closed.**

Close the lid, keep working on an external monitor. Or close it and let a
download, a render, or a backup finish. A left click keeps the Mac up for 20
minutes and then puts it to sleep, so a lid propped open for one task does not
stay open all night.

**Requirements:** macOS 13 or later, Apple Silicon (M1 and newer).

## Install

1. Download `Dusk-1.0.0-macos-arm64.zip` from
   [Releases](https://github.com/kej781004/dusk/releases/latest).
2. Unzip it and drag **Dusk.app** into your **Applications** folder.
3. Open it. **macOS will refuse the first time** — see below.

### The first-open warning

Dusk is not signed with an Apple Developer certificate (those cost $99 a year),
so macOS says it *"cannot be opened because Apple cannot check it for malicious
software."* That message means nobody paid Apple, not that anything is wrong
with the app. To get past it, **once**:

1. Try to open Dusk. Dismiss the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll down. There is a line saying *"Dusk was blocked..."* — click
   **Open Anyway**.
4. Confirm. Dusk opens normally from then on.

If you would rather not take that on faith, the whole app is in this repository
and [builds from source](#build-it-yourself) in about a minute.

## Using it

| Action | Result |
|---|---|
| **Left click** the icon | On for 20 minutes, then the Mac sleeps. Click again to turn it off now. |
| **Right click** (or two-finger click) | The menu: how long to stay awake, what to bring along, low-battery cutoff |

The icon is the switch. `∠` outlined means off, orange means on, and a ring
around it means a countdown is running.

### The menu

- **Keep Awake For** — 15 / 30 / 60 / 120 minutes, or **Until Turned Off** for
  no countdown at all. Countdowns are wall-clock, so they stay honest if the
  Mac sleeps and wakes partway through.
- **Low Power Mode** and **Dim the Screen** — these are *settings*, not
  switches. They decide what turning Dusk on brings with it. Flipping one never
  turns Dusk on or off.
- **Turn Off When Battery Is Low** — a slider, 0 to 100% in steps of 5; 0
  disables it. Below the line, Dusk switches off and tells you. It comes back
  once charging passes the threshold **+5%** (so it does not flicker at the
  boundary), capped at 100% so a threshold near full never waits for a charge
  level that cannot exist.

### When the screen goes black and you cannot find the icon

Press the **brightness-up key (F2)**. Dusk notices and hands the screen back,
even mid-fade. It dims again after five minutes, so turning Dusk off stays a
deliberate act rather than a side effect of wanting to see.

## Why it asks for your password once

There is no way around it: `pmset disablesleep` is **the only** thing that stops
a closed lid from sleeping a Mac — `caffeinate` and display assertions do not
touch that path — and both it and `pmset lowpowermode` live in a root-owned
plist. `IOPMSetValueInt` returns success while silently changing nothing.

So Dusk asks once, and installs a rule permitting exactly these four commands:

```
you ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
you ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1
you ALL=(root) NOPASSWD: /usr/bin/pmset -a lowpowermode 0
you ALL=(root) NOPASSWD: /usr/bin/pmset -a lowpowermode 1
```

No wildcards, so the rule cannot be stretched into running anything else. It
lives at `/etc/sudoers.d/dusk` — read it yourself, and read
[`scripts/install-sudoers.sh`](scripts/install-sudoers.sh), which is what
installs it. Putting a Mac to sleep at the end of a countdown needs no
privileges at all and is not in the rule.

**To remove it:** `sudo rm /etc/sudoers.d/dusk`

## Uninstall

```sh
sudo rm /etc/sudoers.d/dusk
rm -rf /Applications/Dusk.app
defaults delete parkchanbin.Dusk
```

Quitting Dusk already puts `disablesleep` and your brightness back, so there is
nothing else left behind.

## Build it yourself

No Xcode needed — the `.app` is assembled by hand from a SwiftPM build.

```sh
git clone https://github.com/kej781004/dusk.git
cd dusk
make run
```

| | |
|---|---|
| `make check` | 56 checks on the pure logic (XCTest ships with Xcode, so these run as a plain executable) |
| `make install` | check → build → sign → `/Applications` |
| `make run` | all of the above, then launch |
| `make release` | the downloadable zip |

## How it works

```
Sources/DuskCore/     Pure logic. No AppKit, no IOKit — all of it under test
  BrightnessRamp      Elapsed time → brightness. A late timer never overshoots
  PowerSettings       pmset output parsing
  AutoOffPolicy       Low-battery decisions
  DarkGracePolicy     How long the screen is yours after a brightness key
  DuskState           The three switches and the order they move in
Sources/Dusk/         The app
  DisplayBrightness   DisplayServices, a private framework, via dlopen
  DisplayWakeKeeper   IOPMAssertion, so the panel does not sleep at zero
  BatteryMonitor      IOKit power sources
  AutoOffTimer        Wall-clock countdown
  PowerCommands       pmset over sudo, all off the main thread
  DuskController      State, fades, the peek watchdog, sleep and wake
  StatusIcon          The menu bar glyph
  SwitchMenuItemView  A menu row carrying an NSSwitch
  AppDelegate         Clicks, menu, battery and countdown coordination
Sources/DuskCheck/    The verification executable
```

A few things that cost real debugging:

- **Sleep and wake must be handled explicitly.** macOS restores the brightness
  it slept at, so a Mac that slept at zero wakes at zero — and the escape hatch
  only fires when brightness *rises*, so you are stuck in the dark. Worse, a
  watchdog calling into DisplayServices across that transition can block the
  main thread, which in a menu bar app is the spinning beachball. Dusk hands the
  screen back before sleeping and re-dims a second after waking.
- **`sudo -l` cannot answer "can I run this without a password?"** For an admin
  account it says yes with no rule installed at all. Running the command and
  reading the exit status is the only honest test. Every call carries `-n -k`.
- **`pmset` delimiters are not consistent** — `pmset -g custom` uses spaces
  while the global block in `pmset -g` uses tabs. Split on spaces alone and
  `SleepDisabled` silently reads as absent.
- **`pmset` settings and brightness outlive the process.** A force-killed
  instance can leave a Mac that never sleeps behind a screen that will not come
  back, so Dusk clears both at launch and on quit.
- **Event-driven battery watching quietly stops.** IOKit reports power
  *changes*, so a Mac sitting at 100% on the charger produces none at all. A
  60-second re-check runs alongside.

## Credit

A rewrite of [Awayke](https://github.com/daemonphantom/Awayke) in SwiftPM, with
the screen fade, low power rider, and countdown added.

## License

MIT — see [LICENSE](LICENSE). It comes with no warranty: this app changes power
settings and screen brightness on your Mac, and you run it at your own risk.
