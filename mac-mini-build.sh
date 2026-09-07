#!/bin/sh
# Build + install the custom input-leaps server binary for this Mac mini.
#
# See /Applications/InputLeap.app/Contents/MacOS/PATCH-NOTES.md for the
# history and the reasoning behind each step. Summary of the two traps:
#
#   1. SDK STAMP. A binary linked against the macOS 26 SDK has massive mouse
#      lag on the client. Same source, same compiler, same flags; only the
#      `sdk` field in LC_BUILD_VERSION differs. Rewriting it to 14.5 with
#      vtool (no rebuild) removes the lag. Always run the vtool step.
#
#   2. ACCESSIBILITY (TCC). The server is ad-hoc signed, so macOS trusts it
#      by code hash. EVERY new binary must be re-granted manually:
#      System Settings > Privacy & Security > Accessibility:
#      select input-leaps -> "-" ; "+" -> Cmd+Shift+G -> paste the path.
#      Toggling the existing entry off/on does NOT work (the code calls
#      AXIsProcessTrusted() with no prompt option, so macOS never re-asks).
#
# Usage:
#   ./mac-mini-build.sh            # configure + build + vtool + sign -> build/bin/input-leaps.mac-mini
#   ./mac-mini-build.sh --install  # ...and install into InputLeap.app, restart the LaunchAgent
set -eu
cd "$(dirname "$0")"

APP=/Applications/InputLeap.app/Contents/MacOS
IDENT=input-leaps-55554944e00aa5003d4f3f6ea5ac4cf604db28bf   # identifier the original CI binary used
OUT=build/bin/input-leaps.mac-mini

cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DOPENSSL_ROOT_DIR=/opt/homebrew/opt/openssl@3 \
  -DCMAKE_OSX_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14 > build/reconfigure.log
ninja -C build input-leaps > build/build.log

# Trap 1: stamp the SDK version the CI build used, or the client lags.
vtool -set-build-version macos 14.0 14.5 -replace -output "$OUT" build/bin/input-leaps
codesign --sign - --force --identifier "$IDENT" "$OUT" 2>/dev/null
vtool -show-build "$OUT" | grep -E "minos|sdk"
strings "$OUT" | grep -q INPUTLEAP_SHAPE_UNION && echo "main-display edge patch: present"
echo "built: $OUT"

if [ "${1:-}" = "--install" ]; then
  cp "$APP/input-leaps" "$APP/input-leaps.prev"
  cp "$OUT" "$APP/input-leaps"
  launchctl kickstart -k "gui/$(id -u)/com.inputleap.server"
  sleep 3
  if tail -1 /tmp/input-leaps.err | grep -q "assistive devices"; then
    echo "$APP/input-leaps" | pbcopy
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    echo
    echo "Trap 2: not trusted yet. In the Accessibility pane: remove input-leaps, then '+', Cmd+Shift+G,"
    echo "paste (path is on the clipboard), Open. Then: launchctl kickstart -k gui/$(id -u)/com.inputleap.server"
  else
    lsof -i :24800
  fi
fi
