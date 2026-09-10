# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Install

```bash
swift build -c release          # build both targets
./install.sh                    # build + install both binaries + send test notification
```

Binaries land in `.build/release/`: `NotchNotifyApp` (server) and `notch` (CLI).

## Testing manually

```bash
# Server auto-starts on first call if NotchNotifyApp exists next to notch or on PATH
notch "Title" -s "subtitle" -b "body" -i "🚀" -a "OK,Cancel" -t 10 --accent "#34C759"

# Restart server manually
pkill -x NotchNotifyApp; .build/release/NotchNotifyApp &

# Queue demo — fire multiple in quick succession, later ones queue behind first
for i in 1 2 3 4; do notch "Queued #$i" -t 3 >/dev/null & sleep 0.2; done; wait

# Pick queue indicator style (default: both)
NOTCH_QUEUE_STYLE=bar   .build/release/NotchNotifyApp &
NOTCH_QUEUE_STYLE=badge .build/release/NotchNotifyApp &
NOTCH_QUEUE_STYLE=none  .build/release/NotchNotifyApp &

# Pick which screen the notification attaches to (default: main)
NOTCH_SCREEN_TARGET=main  .build/release/NotchNotifyApp &
NOTCH_SCREEN_TARGET=notch .build/release/NotchNotifyApp &

# Force notch-style capsule on a non-notched display (or vice versa)
NOTCH_FORCE=on  .build/release/NotchNotifyApp &   # black capsule everywhere
NOTCH_FORCE=off .build/release/NotchNotifyApp &   # thin pill everywhere
```

## Architecture

Two SPM executable targets sharing a duplicated `Protocol.swift` (SPM limitation — keep both copies in sync):

- **`Sources/NotchNotifyApp/`** — menu-bar app + Unix socket server + SwiftUI notification window
- **`Sources/notch-cli/`** — CLI client; auto-launches server if socket unreachable

### IPC

Unix domain socket at `~/.config/NotchNotify/connect.socket` (mode `0600`). Wire format: one JSON line request → one JSON line response → close. `NotifyRequest` / `NotifyResponse` defined in both `Protocol.swift` copies.

### Notification window (`App.swift`)

`NotchWindow` is a borderless `NSPanel` at `.screenSaver` level. `sharingType` comes from `CaptureVisibility` (`CaptureVisibility.swift`), a persisted `UserDefaults` toggle exposed in the menu bar as "Show in Screenshots & Recordings" (default off = `.none`, hidden from both; macOS gates screenshots and recordings with the same property, so they cannot be split). `NSHostingView` hosts `NotchView`. Window frame `520×320`, pinned top-center of the target display. Default target is `NSScreen.main`; `NOTCH_SCREEN_TARGET=notch` prefers a notched display first.

Visual stack (macOS 26 Tahoe):
- Outermost: `GlassEffectContainer` (required for `glassEffect` to render)
- Card: `.glassEffect(.regular, in: UnevenRoundedRectangle(topLeading:0, topTrailing:0, bottomLeading:24, bottomTrailing:24))` — flat top so it tucks under the capsule
- Icon box: `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 13))`
- Buttons: `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` with `.tint(accent)`
- Text: `.primary` / `.secondary` (vibrancy-adaptive — do NOT use hardcoded `.white`)

### Click-through

The panel is a fixed 520×320 canvas; only the live SwiftUI content rect (top-center anchored, reported via `onGeometryChange` → `fitToContent`) is interactive. `ContentHitRegion` (pure, unit-tested) computes that rect. `NotchWindow` starts with `ignoresMouseEvents = true` and a 30 Hz cursor poll (`updateMousePassthrough`) flips it off only while the cursor is over the content. Returning `nil` from `hitTest` alone is NOT enough — AppKit still routes the click to the panel and swallows it.

### Capsule + animation

`NotchCapsule` picks layout off `hasRealNotch` in `NotchView`:
- `true` → `NotchCapsuleShape` (flat top, rounded bottom), width from `auxiliaryTopLeftArea.maxX` / `auxiliaryTopRightArea.minX`, height from `safeAreaInsets.top`
- `false` → `Capsule()` 4 px tall stand-in

`NotchMode` (`auto` / `on` / `off`, env `NOTCH_FORCE`) overrides detection. In `auto`, notch styling follows the chosen target display only, not any other connected display. When forced `on` without real notch geometry, falls back to `NotchMode.forcedWidth` (180) and `forcedHeight` (32).

`NotchAnim` `@Published` flags drive timing:
- `show()` — `capsuleExpanded = true` immediately (spring 0.38s), `cardShown = true` at +0.18s (spring 0.42s), `queueVisible = true` at +0.55s (spring 0.32s)
- `finish()` — `queueVisible = false` + `cardShown = false` at 0 (ease-in 0.08/0.1s), `capsuleExpanded = false` at +0.1s (spring 0.28s), `orderOut` at +0.36s

### Queue

`NotchPresenter` holds a FIFO array of `Pending(request, completion)`. Concurrent `present()` enqueues + calls `window.updateQueueDepth(n)` which animates `NotchAnim.queueDepth`. On completion, pops next and calls `showNow` — fresh `NotchWindow` with `initialQueueDepth`.

Indicators (both gated on `anim.queueVisible && queueDepth > 0`):
- `QueueBadge` — white circle + black number, overlay on capsule `alignment: .trailing` with offset `(x:-12, y:-1)`. Only rendered when `hasRealNotch`.
- `QueueBar` — separate glass capsule with "N more notification(s)", in `VStack(spacing: 6)` under the card. It is intentionally not merged into the main popover surface, so its material can look slightly different from the card.

`QueueStyle` enum (`bar` / `badge` / `both` / `none`) read once from `NOTCH_QUEUE_STYLE` in `QueueStyle.fromEnv()` at presenter init. Default `both`.

### Socket hardening

`signal(SIGPIPE, SIG_IGN)` in `applicationDidFinishLaunching`. Without this, the CLI's two `canConnect()` probes that close mid-handshake caused the server's `writeJSON()` to get `SIGPIPE` and die silently. Do not remove.

### `-i` / `--image` resolution order

1. `sf:symbol.name` → SF Symbol
2. `http://` or `https://` → `AsyncImage`
3. File path / file URL → `NSImage`
4. Emoji (first scalar > 127 with `isEmoji`) → `Text`
5. Fallback → `sparkles` SF Symbol

### Auto-launch logic (CLI)

`ensureServerRunning()` resolves symlinks on `argv[0]`, looks for `NotchNotifyApp` in the same directory or on `PATH`, launches it directly with `Process` and stdio → `/dev/null`, then polls the socket every 100ms up to 5s.

## Platform

Requires macOS 26.0+. Uses `glassEffect` / `GlassEffectContainer` / `.glass` button styles from SwiftUICore (macOS 26 Tahoe). No backwards compatibility shims.
