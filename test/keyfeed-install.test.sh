#!/usr/bin/env bash
# The installer edits ~/.config/hypr/hyprland.lua, so what it must never do is
# take a line that is not its own. Everything here is about that.
set -euo pipefail

cd "$(dirname "$0")/.."
INSTALL="$PWD/bin/keyfeed-install"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# hyprctl is not running under a test, and the installer must not care.
mkdir -p "$scratch/bin"
printf '#!/bin/sh\nexit 1\n' >"$scratch/bin/hyprctl"
chmod +x "$scratch/bin/hyprctl"
export PATH="$scratch/bin:$PATH"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

BODY='-- my config
monitor("eDP-1", "preferred", "auto", 1)
exec_once("waybar")'

fresh_config() {
  printf '%s\n' "$BODY" >"$scratch/hyprland.lua"
  export HYPRLAND_CONFIG="$scratch/hyprland.lua"
}

# 1. install then uninstall is a round trip, byte for byte.
fresh_config
"$INSTALL" >/dev/null
grep -qF -- '-- sterre.keyboard-hud' "$HYPRLAND_CONFIG" || fail "marker not added"
grep -qF -- "dofile(\"$PWD/keyfeed.lua\")" "$HYPRLAND_CONFIG" || fail "dofile line not added"
"$INSTALL" --uninstall >/dev/null
[ "$(cat "$HYPRLAND_CONFIG")" = "$BODY" ] && pass "round trip leaves the config unchanged" \
  || fail "round trip changed the config: $(cat "$HYPRLAND_CONFIG")"

# 2. the line after the dofile line is somebody else's and must survive. This
#    is the bug: the old uninstaller skipped two lines from the marker.
fresh_config
"$INSTALL" >/dev/null
printf 'exec_once("nm-applet")\n' >>"$HYPRLAND_CONFIG"
"$INSTALL" --uninstall >/dev/null
grep -qxF 'exec_once("nm-applet")' "$HYPRLAND_CONFIG" \
  && pass "the line after the block survives uninstall" \
  || fail "uninstall ate the following line"

# 3. a second install is a no-op rather than a second dofile line.
fresh_config
"$INSTALL" >/dev/null
"$INSTALL" >/dev/null
[ "$(grep -cF -- '-- sterre.keyboard-hud' "$HYPRLAND_CONFIG")" = "1" ] \
  && pass "installing twice adds one block" || fail "installed twice"
"$INSTALL" --uninstall >/dev/null

# 4. a symlinked config is followed, not replaced.
fresh_config
mv "$HYPRLAND_CONFIG" "$scratch/real.lua"
ln -s "$scratch/real.lua" "$HYPRLAND_CONFIG"
"$INSTALL" >/dev/null
[ -L "$HYPRLAND_CONFIG" ] || fail "install replaced the symlink with a regular file"
grep -qF -- '-- sterre.keyboard-hud' "$scratch/real.lua" || fail "install did not reach the target"
"$INSTALL" --uninstall >/dev/null
[ -L "$HYPRLAND_CONFIG" ] && pass "a symlinked config stays a symlink" \
  || fail "uninstall replaced the symlink"
rm -f "$HYPRLAND_CONFIG"

# 5. the mode of the config is the config's, not mktemp's 0600.
fresh_config
chmod 644 "$HYPRLAND_CONFIG"
"$INSTALL" >/dev/null
[ "$(stat -c %a "$HYPRLAND_CONFIG")" = "644" ] && pass "the config keeps its mode" \
  || fail "mode became $(stat -c %a "$HYPRLAND_CONFIG")"
"$INSTALL" --uninstall >/dev/null

# 6. a quote or a backslash in the plugin path is escaped into the Lua literal
#    rather than ending it.
odd="$scratch/we\\ird\"dir"
mkdir -p "$odd/bin"
cp keyfeed.lua "$odd/keyfeed.lua"
cp bin/keyfeed-install "$odd/bin/keyfeed-install"
fresh_config
"$odd/bin/keyfeed-install" >/dev/null
line="$(grep -F 'dofile(' "$HYPRLAND_CONFIG")"
lua="$(command -v lua5.4 || command -v lua || command -v lua5.5 || true)"
if [ -n "$lua" ]; then
  # Reading the literal back with Lua itself is the only honest check that it
  # is one literal and not a literal plus whatever followed it.
  got="$(printf 'print(%s)\n' "${line#dofile(}" | sed 's/)$//' | "$lua" -)"
  [ "$got" = "$odd/keyfeed.lua" ] && pass "an awkward path survives as one Lua literal" \
    || fail "Lua read the path back as: $got"
else
  echo "skip: no lua interpreter for the literal check" >&2
fi
"$odd/bin/keyfeed-install" --uninstall >/dev/null
[ "$(cat "$HYPRLAND_CONFIG")" = "$BODY" ] && pass "and uninstalls cleanly from an awkward path" \
  || fail "awkward path left the config dirty"

# 7. a marker with no matching dofile line is left alone rather than guessed at.
fresh_config
printf '\n-- sterre.keyboard-hud\ndofile("/somewhere/else/keyfeed.lua")\n' >>"$HYPRLAND_CONFIG"
if "$INSTALL" --uninstall >/dev/null 2>&1; then
  fail "uninstall claimed success on a block it did not write"
fi
grep -qF 'dofile("/somewhere/else/keyfeed.lua")' "$HYPRLAND_CONFIG" \
  && pass "a block this plugin did not write is refused, not removed" \
  || fail "uninstall removed a line it could not identify"

echo "keyfeed-install: all checks passed"
