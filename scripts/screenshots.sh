#!/bin/zsh
# screenshots.sh — capture simulator screenshots for the BloggerApp
#
# Usage:
#   ./screenshots.sh                       # screenshot of the current screen
#   ./screenshots.sh -d "iPhone 17 Pro"    # screenshot on a specific device
#   ./screenshots.sh -o /path/to/dir       # save into a custom folder
#   ./screenshots.sh all                   # cycle through app states + screenshots
#
# Output files are named like: 2026-08-09_15-30-00.png (or screenshots/<name>.png for "all")

set -euo pipefail

DEVICE="${SIMULATOR_DEVICE:-iPhone 17 Pro}"
OUT_DIR="$(pwd)/screenshots"
STATE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device)  DEVICE="$2"; shift 2 ;;
    -o|--output)  OUT_DIR="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    all)
      STATE_NAME="all"
      shift
      ;;
    *)
      STATE_NAME="$1"
      shift
      ;;
  esac
done

mkdir -p "$OUT_DIR"

capture() {
  local name="$1"
  local file="$OUT_DIR/${name}.png"
  xcrun simctl io "$DEVICE" screenshot "$file" >/dev/null
  echo "saved: $file"
}

boot_and_launch() {
  xcrun simctl boot "$DEVICE" 2>/dev/null || true
  xcrun simctl launch "$DEVICE" studio.evol.blogger.app >/dev/null 2>&1 || true
  sleep 2
}

if [[ -n "$STATE_NAME" && "$STATE_NAME" != "all" ]]; then
  # Named capture of the current simulator screen.
  capture "$STATE_NAME"
  exit 0
fi

if [[ "$STATE_NAME" == "all" ]]; then
  # Cycle through a few app states and capture each one.
  # Requires the app to be signed in; adjust sleep/actions as needed.
  boot_and_launch
  capture "01-launch"

  sleep 2
  capture "02-home"

  # NOTE: driving the UI programmatically (sign-in, tabs, editor) would need
  # XCUITest or accessibility scripting. Below we just pause for manual
  # navigation between captures.
  echo ">>> Navigate to the next screen manually, then press ENTER to capture."
  read -k1 "?Press ENTER…"; echo
  capture "03-screen"

  echo ">>> Navigate again (e.g. open an editor), then press ENTER to capture."
  read -k1 "?Press ENTER…"; echo
  capture "04-screen"

  echo "All captures saved to: $OUT_DIR"
  exit 0
fi

# Default: single screenshot of whatever is on screen now.
capture "$(date +%Y-%m-%d_%H-%M-%S)"
echo "Screenshot saved to: $OUT_DIR"
