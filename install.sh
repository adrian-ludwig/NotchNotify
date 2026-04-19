#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building..."
swift build -c release

echo "Stopping any running NotchNotifyApp..."
pkill -x NotchNotifyApp 2>/dev/null || true
sleep 0.3

echo "Installing binaries to /usr/local/bin..."
sudo cp .build/release/notch /usr/local/bin/notch
sudo cp .build/release/NotchNotifyApp /usr/local/bin/NotchNotifyApp
sudo chmod 755 /usr/local/bin/notch /usr/local/bin/NotchNotifyApp

echo "Sending showoff notifications (server auto-starts on first use)..."

showoff() {
  # $1 gap seconds; rest forwarded to notch
  local gap="$1"; shift
  notch "$@" >/dev/null &
  sleep "$gap"
}

# 1. Minimal — title only
showoff 3 "Build complete" -t 2

# 2. Title + subtitle, SF Symbol icon, accent
showoff 3.5 "Deploy ready" \
  -s "main branch · production" \
  -i "sf:checkmark.seal.fill" \
  -t 2.5 \
  --accent "#34C759"

# 3. Emoji icon + body
showoff 3.5 "New message" \
  -s "Alice · 2 min ago" \
  -b "hey, you around for a quick call?" \
  -i "💬" \
  -t 2.5 \
  --accent "#0A84FF"

# 4. Two action buttons
showoff 4 "Run tests?" \
  -s "pre-commit hook" \
  -b "23 files changed. Run full suite before push?" \
  -i "sf:testtube.2" \
  -a "Run,Skip" \
  -t 3 \
  --accent "#FF9F0A"

# 5. Destructive-style accent, longer body
showoff 4 "Migration pending" \
  -s "users table · 50M rows" \
  -b "Backfill required before next deploy. Review plan before running." \
  -i "sf:exclamationmark.triangle.fill" \
  -a "Review,Later" \
  -t 3 \
  --accent "#FF453A"

# 6. Finale — glass showoff with three actions
showoff 5 "NotchNotify installed" \
  -s "liquid glass · macOS 26" \
  -b "Dynamic Island style slide in. Ready to ship." \
  -i "✨" \
  -a "Nice,Docs,Close" \
  -t 4 \
  --accent "#BF5AF2"

# 7. Queue demo — fire 4 notifications in quick succession so the
#    2nd/3rd/4th queue behind the 1st. Shows badge on notch + bar under card.
echo "Queue demo — 4 burst notifications..."
notch "Queued #1" -s "showing now" -i "sf:1.circle.fill" -t 3 --accent "#0A84FF" >/dev/null &
sleep 0.25
notch "Queued #2" -s "waiting in line" -i "sf:2.circle.fill" -t 3 --accent "#FF9F0A" >/dev/null &
sleep 0.25
notch "Queued #3" -s "waiting in line" -i "sf:3.circle.fill" -t 3 --accent "#FF453A" >/dev/null &
sleep 0.25
notch "Queued #4" -s "last in line" -i "sf:4.circle.fill" -t 3 --accent "#34C759" >/dev/null &
wait

echo "Done. Run 'notch' anywhere — server launches automatically."
echo "Queue style: NOTCH_QUEUE_STYLE=bar|badge|both|none (default: both)"
