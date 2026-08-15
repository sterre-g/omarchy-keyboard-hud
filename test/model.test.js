const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const M = require("../Model.js")

function run(name, fn) {
  fn()
  process.stdout.write("ok - " + name + "\n")
}

const US = fs.readFileSync(path.join(__dirname, "fixture-us.xkb"), "utf8")
const COLEMAK = fs.readFileSync(path.join(__dirname, "fixture-colemak-dh.xkb"), "utf8")

run("every row is the same width, so the map is a rectangle", () => {
  const widths = M.LAYOUT.map(M.rowUnits)
  for (const width of widths) assert.equal(width, M.ROW_UNITS, "row widths: " + widths.join(", "))
})

run("no keycode appears twice, and both sides of each modifier are present", () => {
  const codes = M.keyCodes()
  assert.equal(new Set(codes).size, codes.length)
  for (const pair of [[50, 62], [37, 105], [64, 108], [133, 134]]) {
    assert.ok(codes.includes(pair[0]) && codes.includes(pair[1]))
  }
})

run("a compiled us keymap gives the qwerty letters", () => {
  const labels = M.parseKeymap(US)
  assert.equal(labels[24], "Q")
  assert.equal(labels[25], "W")
  assert.equal(labels[26], "E")
  assert.equal(labels[38], "A")
  assert.equal(labels[39], "S")
  assert.equal(labels[40], "D")
  assert.equal(labels[52], "Z")
})

run("the same physical keys give colemak letters under colemak", () => {
  const labels = M.parseKeymap(COLEMAK)
  // The qwerty E position carries F, and the qwerty S position carries R.
  assert.equal(labels[26], "F")
  assert.equal(labels[39], "R")
  assert.equal(labels[40], "S")
  assert.equal(labels[27], "P")
  // Q and A do not move in colemak.
  assert.equal(labels[24], "Q")
  assert.equal(labels[38], "A")
})

run("the two layouts genuinely differ, which is the whole point", () => {
  const us = M.parseKeymap(US)
  const colemak = M.parseKeymap(COLEMAK)
  let differences = 0
  for (const code of M.keyCodes()) {
    if (us[code] !== colemak[code]) differences++
  }
  assert.ok(differences >= 10, "expected the letter block to move, saw " + differences)
})

run("punctuation and named keys read as symbols, not keysym names", () => {
  const labels = M.parseKeymap(US)
  assert.equal(labels[59], ",")
  assert.equal(labels[60], ".")
  assert.equal(labels[61], "/")
  assert.equal(labels[22], "Bksp")
  assert.equal(labels[36], "Enter")
  assert.equal(labels[65], "")
})

run("a multi line key block yields its symbols, not its group index", () => {
  // key <RALT> { type= "ONE_LEVEL", symbols[1]= [ ISO_Level3_Shift ] };
  // The first bracket in that block is [1], which is not a keysym.
  const labels = M.parseKeymap(COLEMAK)
  assert.equal(labels[108], "AltGr")
  assert.equal(labels[64], "Alt")
  assert.equal(labels[133], "Super")
  assert.equal(labels[134], "Super")
  assert.equal(labels[37], "Ctrl")
  assert.equal(labels[50], "Shift")
})

run("keysym names map to something a person can read", () => {
  assert.equal(M.labelForKeysym("q"), "Q")
  assert.equal(M.labelForKeysym("7"), "7")
  assert.equal(M.labelForKeysym("F11"), "F11")
  assert.equal(M.labelForKeysym("space"), "")
  assert.equal(M.labelForKeysym("Return"), "Enter")
  assert.equal(M.labelForKeysym("semicolon"), ";")
  assert.equal(M.labelForKeysym("dead_circumflex"), "circ")
  assert.equal(M.labelForKeysym("NoSymbol"), "")
  assert.equal(M.labelForKeysym(""), "")
  assert.equal(M.labelForKeysym(null), "")
})

run("a broken or empty keymap leaves the fallback labels in place", () => {
  assert.deepEqual(M.parseKeymap(""), {})
  assert.deepEqual(M.parseKeymap(null), {})
  assert.deepEqual(M.parseKeymap("nothing useful here"), {})
  assert.equal(M.labelFor(24, {}), "Q")
  assert.equal(M.labelFor(24, null), "Q")
  assert.equal(M.labelFor(9999, null), "")
  assert.equal(M.chordLabelFor(9999, null), "#9999")
  assert.equal(M.chordLabelFor(65, null), "Space")
})

run("chords follow the active layout too", () => {
  const colemak = M.parseKeymap(COLEMAK)
  assert.equal(M.chordText({ mods: [37], code: 26 }, colemak), "Ctrl + F")
  assert.equal(M.chordText({ mods: [37], code: 26 }, M.parseKeymap(US)), "Ctrl + E")
  assert.equal(M.chordText({ mods: [133, 50], code: 42 }, null), "Super + Shift + G")
  assert.equal(M.chordText(null, null), "")
})

run("modifiers are ordered as spoken and deduped", () => {
  assert.deepEqual(M.modifierLabels([50, 37, 133]), ["Super", "Ctrl", "Shift"])
  assert.deepEqual(M.modifierLabels([50, 62]), ["Shift"])
  assert.deepEqual(M.modifierLabels([]), [])
  assert.equal(M.chordText({ mods: [37], code: 37 }, null), "Ctrl")
})

run("content free keys are the ones safe to show without a modifier", () => {
  for (const code of [9, 22, 23, 36, 111, 116, 67, 96]) assert.equal(M.isContentFree(code), true)
  for (const code of [24, 38, 52, 65]) assert.equal(M.isContentFree(code), false)
})

run("one feed line carries both the chord and the held keys", () => {
  const parsed = M.parseFeed('{"t":9,"code":44,"mods":[37],"down":[37,44]}')
  assert.deepEqual(parsed, { t: 9, code: 44, mods: [37], down: [37, 44] })

  const heldOnly = M.parseFeed('{"t":9,"down":[38]}')
  assert.equal(heldOnly.code, null)
  assert.deepEqual(heldOnly.down, [38])

  const chordOnly = M.parseFeed('{"t":9,"code":44,"mods":[]}')
  assert.deepEqual(chordOnly.down, [])
})

run("rubbish in the feed is dropped rather than drawn", () => {
  assert.equal(M.parseFeed("half written {"), null)
  assert.equal(M.parseFeed(""), null)
  assert.equal(M.parseFeed(null), null)
  assert.deepEqual(M.parseFeed('{"down":[38,"x",null,0,-2,50]}').down, [38, 50])
  assert.equal(M.parseFeed('{"code":0}').code, null)
})

run("held keys are matched by code", () => {
  assert.equal(M.isDown([38, 50], 38), true)
  assert.equal(M.isDown([38, 50], 39), false)
  assert.equal(M.isDown(null, 38), false)
})

run("the strip collapses repeats and keeps the newest entries", () => {
  let history = []
  history = M.pushEvent(history, { mods: [37], code: 54 }, 3, null)
  history = M.pushEvent(history, { mods: [37], code: 54 }, 3, null)
  assert.equal(history.length, 1)
  assert.equal(M.displayText(history[0]), "Ctrl + C  x2")

  for (const code of [24, 25, 26]) history = M.pushEvent(history, { mods: [], code: code }, 3, null)
  assert.deepEqual(history.map(h => h.text), ["Q", "W", "E"])
  assert.deepEqual(M.pushEvent([], { mods: [], code: null }, 3, null), [])
})

run("strip entries expire once they have been on screen long enough", () => {
  let history = M.stamp(M.pushEvent([], { mods: [], code: 24 }, 5, null), 1000)
  assert.equal(history[0].shownAt, 1000)
  assert.equal(M.expire(history, 1500, 2000).length, 1)
  assert.equal(M.expire(history, 3500, 2000).length, 0)

  history = M.stamp(history, 5000)
  assert.equal(history[0].shownAt, 1000, "stamping twice must not restart the clock")
})

run("settings normalise, including the stacking order", () => {
  assert.equal(M.normalizeStrip("all"), "all")
  assert.equal(M.normalizeStrip("off"), "off")
  assert.equal(M.normalizeStrip("nonsense"), "chords")
  assert.equal(M.normalizePosition("top"), "top")
  assert.equal(M.normalizePosition("sideways"), "bottom")
  assert.equal(M.normalizeOrder("strip-below"), "strip-below")
  assert.equal(M.normalizeOrder("nonsense"), "strip-above")
  assert.equal(M.stripAbove("strip-above"), true)
  assert.equal(M.stripAbove("strip-below"), false)
  assert.equal(M.normalizeBool("true"), true)
  assert.equal(M.normalizeBool(undefined), false)
  assert.equal(M.normalizeScale(9), 2)
  assert.equal(M.normalizeScale("junk"), 1)
})

run("the keyboard to follow is a real one, not the input method's virtual pair", () => {
  const keyboards = [
    { name: "hl-virtual-keyboard-fcitx5", layout: "us", variant: "", main: true },
    { name: "at-translated-set-2-keyboard", layout: "us", variant: "colemak_dh_wide_iso" }
  ]
  assert.equal(M.pickKeyboard(keyboards).name, "at-translated-set-2-keyboard")

  const noVariant = [
    { name: "hl-virtual-keyboard-fcitx5", layout: "us", variant: "" },
    { name: "logitech-g305", layout: "us", variant: "" }
  ]
  assert.equal(M.pickKeyboard(noVariant).name, "logitech-g305")

  const onlyVirtual = [{ name: "hl-virtual-keyboard-fcitx5", layout: "us", variant: "" }]
  assert.equal(M.pickKeyboard(onlyVirtual).name, "hl-virtual-keyboard-fcitx5")
  assert.equal(M.pickKeyboard([]), null)
  assert.equal(M.pickKeyboard(null), null)
})

run("the compile command follows the keyboard, and an override wins", () => {
  const keyboard = { name: "kb", layout: "us", variant: "colemak_dh_wide_iso" }
  assert.deepEqual(M.keymapCommand(keyboard, null),
    ["xkbcli", "compile-keymap", "--layout", "us", "--variant", "colemak_dh_wide_iso"])
  assert.deepEqual(M.keymapCommand({ name: "kb", layout: "de", variant: "" }, null),
    ["xkbcli", "compile-keymap", "--layout", "de"])
  assert.deepEqual(M.keymapCommand(keyboard, { layout: "dvorak", variant: "" }),
    ["xkbcli", "compile-keymap", "--layout", "dvorak"])
  assert.deepEqual(M.keymapCommand(null, null), ["xkbcli", "compile-keymap", "--layout", "us"])

  assert.equal(M.layoutName(keyboard, null), "us colemak_dh_wide_iso")
  assert.equal(M.layoutName({ layout: "de", variant: "" }, null), "de")
  assert.equal(M.layoutName(null, { layout: "fr", variant: "azerty" }), "fr azerty")
})

process.stdout.write("\nall Model.js tests passed\n")
