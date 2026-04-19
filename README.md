# NotchNotify

Screen-recording-invisible notifications for macOS that live around the notch. Comes with a CLI so your agent can ping you and read your response.

- **Invisible to screen recording / screen sharing** — uses `NSWindowSharingNone`, excluded from QuickTime, Zoom, Meet, ScreenCaptureKit.
- **No notification permission** — draws its own floating window, never touches `UNUserNotificationCenter`.
- **Floats above everything** — shows over fullscreen apps, all Spaces, never steals focus.
- **Rich content** — image (file path or SF Symbol), title, subtitle, body, action buttons.
- **Fast keyboard actions** — `Return` = primary, `Esc` = dismiss.
- **Glass styling** — `NSVisualEffectView` with Tahoe-style materials.

## Build

Requires Xcode 15+ and macOS 14+ (Sonoma or newer).

```bash
swift build -c release
```

Produces two binaries in `.build/release/`:
- `NotchNotifyApp` — the menu-bar app (server)
- `notch` — the CLI (client)

## Install

```bash
# 1. Run the app (it lives in the menu bar, no Dock icon)
./.build/release/NotchNotifyApp &

# 2. Put the CLI on your PATH
sudo cp .build/release/notch /usr/local/bin/notch

# 3. Try it
notch "Hello" -s "from NotchNotify" -b "It works!" -a OK,Cancel -t 10
```

For a proper install (auto-start on login, real `.app` bundle), open `Package.swift` in Xcode, **Product → Archive**, then drag the resulting app to `/Applications` and add it to System Settings → General → Login Items.

## CLI

```
notch "Title" [options]

  -s, --subtitle TEXT       Small secondary line
  -b, --body TEXT           Longer description
  -i, --image VALUE         Image path OR "sf:symbol.name" for an SF Symbol
  -a, --actions A,B,C       Action buttons (first one is "primary")
  -t, --timeout SECS        Auto-dismiss after N seconds
      --style glass|solid   Visual style (default: glass)
      --accent #RRGGBB      Primary button color
```

Stdout is one JSON line: `{"action":"Accept","dismissed":false}`

Exit codes: `0` = first action, `1` = any other action, `2` = dismissed, `3` = error.

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

- **Window:** a borderless `NSPanel` pinned to the top-center of the main screen. `level = .screenSaver` puts it above fullscreen apps; `collectionBehavior` includes `.fullScreenAuxiliary` + `.canJoinAllSpaces`.
- **Invisibility to recording:** `window.sharingType = .none`. macOS excludes the window from every capture API.
- **No permission prompt:** we never use `UNUserNotificationCenter`. It's just a window.
- **IPC:** Unix domain socket at `~/.config/NotchNotify/connect.socket`, mode `0600` (directory `0700`). Honors `XDG_CONFIG_HOME` if set. One JSON line request → one JSON line response → close.
- **Notch awareness:** on notched displays (`NSScreen.safeAreaInsets.top > 0`) the card is pushed down past the notch.
- **Multiple notifications:** currently the presenter replaces any active notification with a new one. Change `NotchPresenter` if you want queueing or stacking.

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

- **Visuals:** `NotchView` in `App.swift` — swap `VisualEffectBlur` material (`.hudWindow`, `.fullScreenUI`, `.popover`, `.underWindowBackground`), change corner radius, padding, colors.
- **Window size / position:** `NotchWindow.init` — edit the `size` NSSize and the `y` calculation.
- **Queue vs replace:** currently the presenter replaces any active notification with the new one. For queueing, buffer requests in `NotchPresenter`.
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
