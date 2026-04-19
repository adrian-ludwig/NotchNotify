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

echo "Sending test notification (server auto-starts on first use)..."
notch "NotchNotify installed" \
  -s "build complete" \
  -b "Liquid glass is live." \
  -i "✅" \
  -a "Nice,Dismiss" \
  -t 10 \
  --accent "#34C759"

echo "Done. Run 'notch' anywhere — server launches automatically."
