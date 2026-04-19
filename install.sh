#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building..."
swift build -c release

echo "Stopping any running NotchNotifyApp..."
pkill -x NotchNotifyApp 2>/dev/null || true
sleep 0.3

echo "Installing notch CLI to /usr/local/bin..."
sudo cp .build/release/notch /usr/local/bin/notch

echo "Launching NotchNotifyApp..."
.build/release/NotchNotifyApp &
sleep 0.5

echo "Sending test notification..."
notch "NotchNotify installed" \
  -s "build complete" \
  -b "Liquid glass is live." \
  -i "sf:checkmark.seal.fill" \
  -a "Nice,Dismiss" \
  -t 10 \
  --accent "#34C759" &

echo "Done. notch CLI at /usr/local/bin/notch, app running in menu bar."
