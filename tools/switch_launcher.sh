#!/usr/bin/env bash
# Quick Launcher Switcher for Android TV.
# Allows instantly switching the default home screen between your personal launcher,
# the Apple TV makeover launcher, CleanYourTV, or the factory stock Kodak launcher.
#
# Usage:
#   ./tools/switch_launcher.sh makeover    # Switch to Apple TV Makeover launcher
#   ./tools/switch_launcher.sh cleanyourtv # Switch to CleanYourTV launcher
#   ./tools/switch_launcher.sh stock       # Switch back to stock Google Android TV launcher
#   ./tools/switch_launcher.sh personal    # Switch to your custom personal launcher
#   ./tools/switch_launcher.sh list        # List all installed launchers and active home
set -euo pipefail

cd "$(dirname "$0")/.."
TV_HOST="${TV_HOST:-192.168.29.198}"
export TV_HOST

PY=.venv/bin/python
if [ ! -x "$PY" ]; then
  PY=python3
fi

TARGET="${1:-}"

get_activity() {
  case "$1" in
    makeover) echo "com.kulwant.atvhome/.HomeActivity" ;;
    cleanyourtv) echo "com.gathin.tvhome/.MainActivity" ;;
    personal) echo "com.personal.tvhome/.MainActivity" ;;
    stock) echo "com.google.android.tvlauncher/.MainActivity" ;;
    *) echo "" ;;
  esac
}

list_launchers() {
  echo "Checking active home and installed launchers on TV ($TV_HOST)..."
  "$PY" tools/tv.py "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME"
  echo ""
  echo "Available switch targets:"
  for k in makeover cleanyourtv personal stock; do
    echo "  - $k -> $(get_activity "$k")"
  done
}

if [ -z "$TARGET" ] || [ "$TARGET" = "list" ] || [ "$TARGET" = "--list" ]; then
  list_launchers
  exit 0
fi

TARGET_ACTIVITY="$(get_activity "$TARGET")"
if [ -z "$TARGET_ACTIVITY" ]; then
  echo "Unknown launcher: '$TARGET'" >&2
  echo "Valid options: makeover | cleanyourtv | personal | stock | list" >&2
  exit 1
fi

PKG="${TARGET_ACTIVITY%%/*}"
echo "Switching default TV Home to: $TARGET ($TARGET_ACTIVITY)..."

# Ensure package is enabled (in case it was disabled previously)
"$PY" tools/tv.py "pm enable $PKG" || true

# Set as default home activity
"$PY" tools/tv.py "cmd package set-home-activity $TARGET_ACTIVITY"

# Wake display and bring launcher to foreground
"$PY" tools/tv.py "input keyevent KEYCODE_HOME"

echo "Switched to $TARGET successfully! Pressing Home on the TV remote now opens $TARGET."
