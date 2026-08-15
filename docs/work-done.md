# Work done

## 2026-08-15 - first release

- `feat/combined-hud`: one plugin doing what `omarchy-key-visualizer` and
  `omarchy-keyboard-minimap` did separately, so the key strip and the keyboard
  map can be stacked in either order. One lua feed, one install script, one
  set of settings.
- The map follows the loaded keyboard layout: `hyprctl -j devices` for the
  layout and variant, `xkbcli compile-keymap` for the symbols, parsed in
  `Model.js`. Two real compiled keymaps are checked in as fixtures, and a test
  asserts qwerty and colemak differ on the same keycodes.
- The keyboard Hyprland flags as `main` is often an input method virtual
  keyboard with no variant, so a real device with a variant wins, with a manual
  override available.
- Both halves are gated in lua rather than in QML: the strip drops plain typing
  in its default chords mode, and the map records nothing until it is on.
- Fixed before merge: the overlay had no input region, so while the map was on
  its full width strip swallowed every click inside it, including on the bar
  underneath. `mask: Region {}` makes it click through, which is what the first
  party OSD does for the same reason.
