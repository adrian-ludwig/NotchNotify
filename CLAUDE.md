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
# Server auto-starts on first call if /usr/local/bin/NotchNotifyApp exists next to notch
notch "Title" -s "subtitle" -b "body" -i "🚀" -a "OK,Cancel" -t 10 --accent "#34C759"

# Restart server manually
pkill -x NotchNotifyApp; .build/release/NotchNotifyApp &
```

## Architecture

Two SPM executable targets sharing a duplicated `Protocol.swift` (SPM limitation — keep both copies in sync):

- **`Sources/NotchNotifyApp/`** — menu-bar app + Unix socket server + SwiftUI notification window
- **`Sources/notch-cli/`** — CLI client; auto-launches server if socket unreachable

### IPC

Unix domain socket at `~/.config/NotchNotify/connect.socket` (mode `0600`). Wire format: one JSON line request → one JSON line response → close. `NotifyRequest` / `NotifyResponse` defined in both `Protocol.swift` copies.

### Notification window (`App.swift`)

`NotchWindow` is a borderless `NSPanel` at `.screenSaver` level, `sharingType = .none` (invisible to screen recording). `NSHostingView` hosts `NotchView`.

Visual stack (macOS 26 Tahoe):
- Outermost: `GlassEffectContainer` (required for `glassEffect` to render)
- Card: `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))`
- Icon box: `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 13))`
- Buttons: `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` with `.tint(accent)`
- Text: `.primary` / `.secondary` (vibrancy-adaptive — do NOT use hardcoded `.white`)

### `-i` / `--image` resolution order

1. `sf:symbol.name` → SF Symbol
2. `http://` or `https://` → `AsyncImage`
3. File path / file URL → `NSImage`
4. Emoji (first scalar > 127 with `isEmoji`) → `Text`
5. Fallback → `sparkles` SF Symbol

### Auto-launch logic (CLI)

`ensureServerRunning()` resolves symlinks on `argv[0]`, looks for `NotchNotifyApp` in the same directory, launches it with stdio → `/dev/null`, polls socket every 100ms up to 3s.

## Platform

Requires macOS 26.0+. Uses `glassEffect` / `GlassEffectContainer` / `.glass` button styles from SwiftUICore (macOS 26 Tahoe). No backwards compatibility shims.
