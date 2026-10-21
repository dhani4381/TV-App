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

declare -A LAUNCHERS
LAUNCHERS["makeover"]="com.kulwant.atvhome/.HomeActivity"
LAUNCHERS["cleanyourtv"]="com.gathin.tvhome/.MainActivity"
LAUNCHERS["personal"]="com.personal.tvhome/.MainActivity"
LAUNCHERS["stock"]="com.google.android.tvlauncher/.MainActivity"

list_launchers() {
  echo "Checking active home and installed launchers on TV ($TV_HOST)..."
  "$PY" tools/tv.py "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME"
  echo ""
  echo "Available switch targets:"
  for k in makeover cleanyourtv personal stock; do
    echo "  - $k -> ${LAUNCHERS[$k]}"
  done
}

if [ -z "$TARGET" ] || [ "$TARGET" = "list" ] || [ "$TARGET" = "--list" ]; then
  list_launchers
  exit 0
fi

TARGET_ACTIVITY="${LAUNCHERS[$TARGET]:-}"
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

# Launch it on screen
"$PY" tools/tv.py "am start -n $TARGET_ACTIVITY"

echo "Successfully switched default Home to: $TARGET"
