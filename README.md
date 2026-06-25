# NotchNotify

Screen-recording-invisible notifications for macOS that live around the notch. Comes with a CLI so your agent can ping you and read your response.

- **Invisible to screen recording / screen sharing** — uses `NSWindowSharingNone`, excluded from QuickTime, Zoom, Meet, ScreenCaptureKit.
- **No notification permission** — draws its own floating window, never touches `UNUserNotificationCenter`.
- **Floats above everything** — shows over fullscreen apps, all Spaces, never steals focus.
- **Rich content** — image (emoji, local file, `https://` URL, or SF Symbol), title, subtitle, body, action buttons.
- **Fast keyboard actions** — `Return` = primary, `Esc` = dismiss.
- **Dynamic Island animation** — capsule expands from the notch, card slides from under it; thin pill on non-notched displays.
- **Queue with live indicators** — concurrent requests queue FIFO; white badge on the capsule and/or a glass bar under the card show how many are waiting.
- **Glass styling** — macOS 26 Tahoe liquid glass (`glassEffect`, `GlassEffectContainer`, `.glass` / `.glassProminent` button styles).

## Build

Requires Xcode 16+ and **macOS 26 Tahoe** or newer (liquid glass APIs).

```bash
swift build -c release
```

Produces two binaries in `.build/release/`:
- `NotchNotifyApp` — the menu-bar app (server)
- `notch` — the CLI (client)

## Install

One-shot script: build, stop any running app, install both binaries to a **user-owned** directory, adhoc re-sign them, then run a showoff reel (including a 4-notification queue demo):

```bash
./install.sh
```

Install dir is picked in this order: `$NOTCH_INSTALL_DIR` → `/opt/homebrew/bin` (if writable) → `~/.local/bin`.

```bash
NOTCH_INSTALL_DIR=~/bin ./install.sh   # override
```

**Don't `sudo cp` into `/usr/local/bin`.** `swift build` emits an *adhoc, linker-signed* binary the kernel only honors at its original build path; copying it to a root-owned path makes macOS reject the launch with `Taskgated Invalid Signature` (SIGKILL). `install.sh` sidesteps this by copying to a user-owned dir and re-signing (`codesign --force --sign -`). Manual equivalent:

```bash
cp .build/release/notch .build/release/NotchNotifyApp ~/.local/bin/
codesign --force --sign - ~/.local/bin/notch ~/.local/bin/NotchNotifyApp
notch "Hello" -s "from NotchNotify" -b "It works!" -a OK,Cancel -t 10
```

`notch` auto-launches `NotchNotifyApp` if the socket is unreachable, as long as both binaries live in the same directory (or `NotchNotifyApp` is on `PATH`).

For login-time auto-start, open `Package.swift` in Xcode, **Product → Archive**, drop the resulting app into `/Applications`, add to System Settings → General → Login Items.

## CLI

```
notch "Title" [options]

  -s, --subtitle TEXT       Small secondary line
  -b, --body TEXT           Longer description
  -i, --image VALUE         Emoji, file path, https:// URL, or "sf:symbol.name"
  -a, --actions A,B,C       Action buttons (first one is "primary")
  -t, --timeout SECS        Auto-dismiss after N seconds
      --style glass|solid   Visual style (default: glass)
      --accent #RRGGBB      Primary button color
  -n, --no-wait             Fire and exit immediately; don't wait for a response
```

Stdout is one JSON line: `{"action":"Accept","dismissed":false}`

Exit codes: `0` = first action, `1` = any other action, `2` = dismissed, `3` = error.
With `--no-wait` the CLI exits `0` as soon as the request is delivered (`3` if the server is unreachable) and prints nothing — use it for passive, action-less toasts that auto-dismiss on their own timer.

### Environment

- `NOTCH_QUEUE_STYLE` = `bar` | `badge` | `both` | `none` — picks how the pending-queue depth is displayed while a notification is visible. Default `both`. `badge` is automatically hidden on displays without a real notch. Read once by the server on launch; restart the app to change it.
- `NOTCH_FORCE` = `on` | `off` | `auto` — overrides notch detection. `on` forces the black capsule + badge even on non-notched displays (uses a 180×32 fallback when no real notch geometry is available); `off` forces the thin glass pill on every display. Default `auto` (detects from the chosen target display, not from all connected displays).
- `NOTCH_SCREEN_TARGET` = `main` | `notch` — picks which display the notification window attaches to. Default `main`. `notch` restores the old behavior of preferring a notched display first. Read once by the server on launch; restart the app to change it.

## Compositions

Every card has a thumbnail (left) and a title (required). Everything else is optional and stacks. The tables below cover every combination the renderer supports.

### Content layout

`title` and the thumbnail always render. `subtitle`, `body`, and `actions` are independent — mix freely.

| subtitle | body | actions | Looks like | Command |
|:--------:|:----:|:-------:|------------|---------|
| – | – | – | bare toast | `notch "Build complete"` |
| ✓ | – | – | toast + context line | `notch "Deploy ready" -s "main · prod"` |
| – | ✓ | – | toast + paragraph | `notch "Heads up" -b "Backfill finished."` |
| ✓ | ✓ | – | full text card | `notch "New DM" -s "Alice" -b "you around?"` |
| – | – | 1 | one-tap confirm | `notch "Continue?" -a OK` |
| ✓/✓ | – | 2 | yes/no prompt | `notch "Run tests?" -s "pre-commit" -a Yes,No` |
| ✓ | ✓ | 3+ | rich prompt | `notch "Installed" -s "v2" -b "Ready." -a Nice,Docs,Close` |

First action is primary (accent-tinted, `Return`); `Esc` / close button dismisses. Action result comes back on stdout + exit code (unless `--no-wait`).

### Thumbnail source (`-i`)

| Value | Renders |
|-------|---------|
| `🚀` (any emoji) | the emoji glyph |
| `sf:bell.badge.fill` | SF Symbol, tinted with `--accent` |
| `~/avatars/alice.png`, `/abs/img.jpg` | local image file |
| `https://example.com/img.png` | remote image (async-loaded) |
| omitted / load fails | `sparkles` fallback glyph |

### Modifiers (orthogonal — combine with any layout)

| Flag / env | Effect |
|------------|--------|
| `-t SECS` | auto-dismiss after N seconds |
| `--style glass\|solid` | translucent liquid glass (default) vs. darker solid fill |
| `--accent #RRGGBB` | primary-button + SF-symbol tint |
| `-n, --no-wait` | fire-and-forget; exit `0` immediately, no response |
| `NOTCH_QUEUE_STYLE=bar\|badge\|both\|none` | how queued-notification depth is shown |
| `NOTCH_FORCE=on\|off\|auto` | force capsule / pill / auto-detect |
| `NOTCH_SCREEN_TARGET=main\|notch` | which display to attach to |

### Display variants (automatic)

| Display | Presentation |
|---------|--------------|
| Notched Mac | black capsule expands from the notch, card slides under it; queue **badge** sits inside the capsule |
| Non-notched | thin glass **pill** stands in for the capsule; queue shown as a **bar** under the card |

Concurrent `notch` calls queue FIFO — the first shows, the rest wait, and the live badge/bar counts how many are pending.

## Examples

```bash
# Simple toast
notch "Build finished"

# Agent asking a question
notch "Deploy ready?" \
  -s "main · 3 commits ahead" \
  -b "Run the production deploy now?" \
  -i sf:arrow.up.circle.fill \
  -a Deploy,Cancel \
  -t 60 \
  --accent "#34C759"

# DM-style with avatar
notch "Alice" -s "direct message" -i ~/avatars/alice.png -b "you around?" -a Reply,Later

# Use from a shell script
response=$(notch "Run tests?" -a Yes,No -t 30)
case $? in
  0) npm test ;;
  1) echo "Skipping tests." ;;
  2) echo "No response." ;;
esac
```

### From Python

```python
import subprocess, json
r = subprocess.run(
    ["notch", "Agent question", "-b", "Commit these changes?", "-a", "Yes,No", "-t", "60"],
    capture_output=True, text=True,
)
result = json.loads(r.stdout) if r.stdout.strip() else {}
print(result.get("action"))  # "Yes", "No", or None
```

## How it works

- **Window:** a borderless `NSPanel` pinned to the top-center of the target screen. By default that is the main screen; if macOS does not report one, it falls back to a notched display and then any display. Set `NOTCH_SCREEN_TARGET=notch` to prefer a notched display first. `level = .screenSaver` puts it above fullscreen apps; `collectionBehavior` includes `.fullScreenAuxiliary` + `.canJoinAllSpaces`.
- **Invisibility to recording:** `window.sharingType = .none`. macOS excludes the window from every capture API.
- **No permission prompt:** we never use `UNUserNotificationCenter`. It's just a window.
- **IPC:** Unix domain socket at `~/.config/NotchNotify/connect.socket`, mode `0600` (directory `0700`). Honors `XDG_CONFIG_HOME` if set. One JSON line request → one JSON line response → close. Server ignores `SIGPIPE` so a CLI probe that hangs up mid-write does not kill the app.
- **Notch awareness:** `NSScreen.safeAreaInsets.top > 0` on the chosen target display picks notched layout (`NotchCapsuleShape`: flat top, rounded bottom, width from `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`). Otherwise a thin glass pill stands in for the capsule. `NOTCH_FORCE` can override this per launch.
- **Animation:** capsule expands from notch width to card width (spring, ~380 ms), card slides down from under the capsule with only the bottom corners rounded so it tucks under (`UnevenRoundedRectangle`). Dismissal: card retracts (~100 ms), capsule contracts (~280 ms), window closes at ~360 ms.
- **Queue:** `NotchPresenter` holds a FIFO queue. When a request arrives while one is visible it's appended and `NotchAnim.queueDepth` is updated live on the current window. A white circle badge sits inside the capsule (notched only) and/or a glass bar sits under the card with a 6 px gap. The queue bar is intentionally a separate glass surface, so it can sample material independently from the main card rather than appearing as one merged popover. Both fade in only after the expansion finishes (`queueVisible` flag, +550 ms). Style chosen via `NOTCH_QUEUE_STYLE`.

## File layout

```
NotchNotify/
├── Package.swift
├── Sources/
│   ├── NotchNotifyApp/     ← menu-bar app + socket server + notch window
│   │   ├── App.swift
│   │   └── Protocol.swift
│   └── notch-cli/          ← CLI client
│       ├── main.swift
│       └── Protocol.swift
└── README.md
```

`Protocol.swift` is intentionally duplicated — SPM executable targets can't share source files without adding a library target. Keep the two copies in sync if you edit the wire format.

## Customizing

- **Visuals:** `NotchView` in `App.swift` — adjust glass materials (`glassEffect(.regular, …)`), corner radius, padding, card width (`cardWidth = 460`), capsule overlap (`capsuleOverlap = 8`).
- **Window size / position:** `NotchWindow.init` — edit the `size` NSSize (currently `520×320`) and the `y` calculation.
- **Animation timing:** `show()` and `finish()` in `NotchWindow` — tune spring response / damping and the `asyncAfter` offsets for capsule-expand, card-slide, badge/bar fade-in (`queueVisible`).
- **Queue UI:** `QueueBadge` and `QueueBar` in `App.swift`. `QueueStyle.fromEnv()` picks which one(s) render. `NotchPresenter.queue` is a plain FIFO — swap for LIFO, coalescing, or drop-oldest if needed.
- **More fields:** add to `NotifyRequest` in *both* `Protocol.swift` files, then render them in `NotchView` and parse them in the CLI.

## Making a proper .app bundle

For real daily use you want an `.app` with `LSUIElement=true` in `Info.plist` (fully menu-bar-only). Easiest path:

1. Open `Package.swift` in Xcode.
2. File → New → Target → macOS App. Name it `NotchNotify`. Use SwiftUI.
3. Move the contents of `Sources/NotchNotifyApp/*.swift` into the new app target.
4. In the target's Info settings, add `Application is agent (UIElement)` = `YES`.
5. **Product → Archive**, then distribute as "Copy App".
6. Drag to `/Applications`, add to Login Items.

## Troubleshooting

- **"Could not reach NotchNotify app"** — the menu-bar app isn't running.
- **Shows up in my screen recording** — you're running a debug build that isn't applying `sharingType` yet, or the recorder uses a pre-ScreenCaptureKit path. Test with `-c release`.
- **Stale socket after a crash** — `rm ~/.config/NotchNotify/connect.socket` and restart.
- **No bell icon in menu bar** — macOS may have hidden it if your menu bar is full; try Bartender or check `defaults` for hidden items.

## License

MIT.
