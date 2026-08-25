// The physical keyboard, as rows of [x11 keycode, fallback label, width in key
// units]. Positions and keycodes are physical and do not move when the layout
// changes; only the labels do, and those come from the compiled keymap.
var LAYOUT = [
  [
    [9, "Esc", 1], [10, "1", 1], [11, "2", 1], [12, "3", 1], [13, "4", 1], [14, "5", 1],
    [15, "6", 1], [16, "7", 1], [17, "8", 1], [18, "9", 1], [19, "0", 1],
    [20, "-", 1], [21, "=", 1], [22, "Bksp", 2]
  ],
  [
    [23, "Tab", 1.5], [24, "Q", 1], [25, "W", 1], [26, "E", 1], [27, "R", 1], [28, "T", 1],
    [29, "Y", 1], [30, "U", 1], [31, "I", 1], [32, "O", 1], [33, "P", 1],
    [34, "[", 1], [35, "]", 1], [51, "\\", 1.5]
  ],
  [
    [66, "Caps", 1.75], [38, "A", 1], [39, "S", 1], [40, "D", 1], [41, "F", 1], [42, "G", 1],
    [43, "H", 1], [44, "J", 1], [45, "K", 1], [46, "L", 1], [47, ";", 1], [48, "'", 1],
    [36, "Enter", 2.25]
  ],
  [
    [50, "Shift", 2.25], [52, "Z", 1], [53, "X", 1], [54, "C", 1], [55, "V", 1], [56, "B", 1],
    [57, "N", 1], [58, "M", 1], [59, ",", 1], [60, ".", 1], [61, "/", 1],
    [62, "Shift", 2.75]
  ],
  [
    [37, "Ctrl", 1.25], [133, "Super", 1.25], [64, "Alt", 1.25], [65, "", 6.25],
    [108, "Alt", 1.25], [134, "Super", 1.25], [135, "Menu", 1.25], [105, "Ctrl", 1.25]
  ]
]

var ROW_UNITS = 15

var MODIFIERS = {
  37: "Ctrl", 105: "Ctrl", 50: "Shift", 62: "Shift",
  64: "Alt", 108: "Alt", 133: "Super", 134: "Super"
}

var MOD_ORDER = ["Super", "Ctrl", "Alt", "Shift"]

// Keys that carry no typed text, so the strip may show them without a modifier
// held even in chords mode.
var CONTENT_FREE = [
  9, 22, 23, 36, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 95, 96, 107,
  110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 121, 122, 123, 135,
  171, 172, 173, 174
]

var KEYSYM_LABELS = {
  space: "", Return: "Enter", BackSpace: "Bksp", Tab: "Tab", Escape: "Esc",
  Caps_Lock: "Caps", Shift_L: "Shift", Shift_R: "Shift", Control_L: "Ctrl",
  Control_R: "Ctrl", Alt_L: "Alt", Alt_R: "Alt", ISO_Level3_Shift: "AltGr",
  Super_L: "Super", Super_R: "Super", Menu: "Menu",
  comma: ",", period: ".", slash: "/", semicolon: ";", apostrophe: "'",
  bracketleft: "[", bracketright: "]", backslash: "\\", minus: "-", equal: "=",
  grave: "`", quoteleft: "`", exclam: "!", at: "@", numbersign: "#",
  dollar: "$", percent: "%", asciicircum: "^", ampersand: "&", asterisk: "*",
  parenleft: "(", parenright: ")", underscore: "_", plus: "+",
  less: "<", greater: ">", question: "?", colon: ":", quotedbl: "\"",
  bar: "|", asciitilde: "~", braceleft: "{", braceright: "}",
  Up: "Up", Down: "Down", Left: "Left", Right: "Right",
  Home: "Home", End: "End", Prior: "PgUp", Next: "PgDn",
  Insert: "Ins", Delete: "Del", Print: "Print"
}

function labelForKeysym(keysym) {
  var name = String(keysym || "").trim()
  if (name === "" || name === "NoSymbol" || name === "VoidSymbol") return ""
  if (KEYSYM_LABELS.hasOwnProperty(name)) return KEYSYM_LABELS[name]
  if (/^[a-z]$/.test(name)) return name.toUpperCase()
  if (/^[0-9]$/.test(name)) return name
  if (/^F([1-9]|1[0-9]|2[0-4])$/.test(name)) return name
  if (/^dead_/.test(name)) return name.replace("dead_", "").slice(0, 4)
  if (name.length <= 4) return name
  return name.slice(0, 4)
}

// xkbcli compile-keymap prints the keycode names and their symbol lists in two
// sections. Reading the compiled keymap rather than shipping a table per
// layout is what makes this work for colemak, dvorak, azerty and anything else
// the user has actually configured.
function parseKeymap(text) {
  var raw = String(text || "")
  if (raw === "") return {}

  var codeByName = {}
  var codeLine = /^\s*<([A-Za-z0-9_+\-]+)>\s*=\s*(\d+);/gm
  var match
  while ((match = codeLine.exec(raw)) !== null) {
    codeByName[match[1]] = Number(match[2])
  }

  var labels = {}
  var symbolLine = /key\s+<([A-Za-z0-9_+\-]+)>\s*\{([^}]*)\}/g
  while ((match = symbolLine.exec(raw)) !== null) {
    var code = codeByName[match[1]]
    if (code === undefined) continue
    var inner = match[2]
    // A multi line block writes "symbols[1]= [ ISO_Level3_Shift ]", so the
    // first bracket in the block is the group index rather than the symbols.
    var listMatch = /symbols\[[^\]]*\]\s*=\s*\[([^\]]*)\]/.exec(inner)
      || /\[([^\]]*)\]/.exec(inner)
    if (!listMatch) continue
    var first = listMatch[1].split(",")[0]
    var label = labelForKeysym(first)
    if (label !== "" || code === 65) labels[code] = label
  }
  return labels
}

function labelFor(code, keymapLabels) {
  if (keymapLabels && keymapLabels.hasOwnProperty(code)) return keymapLabels[code]
  for (var r = 0; r < LAYOUT.length; r++) {
    for (var k = 0; k < LAYOUT[r].length; k++) {
      if (LAYOUT[r][k][0] === code) return LAYOUT[r][k][1]
    }
  }
  return ""
}

function chordLabelFor(code, keymapLabels) {
  var label = labelFor(code, keymapLabels)
  if (label !== "") return label
  if (code === 65) return "Space"
  return "#" + code
}

function rowUnits(row) {
  var total = 0
  var keys = row || []
  for (var i = 0; i < keys.length; i++) total += keys[i][2]
  return Math.round(total * 100) / 100
}

function keyCodes() {
  var out = []
  for (var r = 0; r < LAYOUT.length; r++) {
    for (var k = 0; k < LAYOUT[r].length; k++) out.push(LAYOUT[r][k][0])
  }
  return out
}

function isModifier(code) {
  return MODIFIERS[code] !== undefined
}

function isContentFree(code) {
  return CONTENT_FREE.indexOf(code) !== -1
}

function modifierLabels(codes) {
  var seen = {}
  var list = codes || []
  for (var i = 0; i < list.length; i++) {
    var label = MODIFIERS[list[i]]
    if (label) seen[label] = true
  }
  var out = []
  for (var m = 0; m < MOD_ORDER.length; m++) {
    if (seen[MOD_ORDER[m]]) out.push(MOD_ORDER[m])
  }
  return out
}

function chordText(event, keymapLabels) {
  if (!event) return ""
  var parts = modifierLabels(event.mods)
  if (event.code !== undefined && event.code !== null && !isModifier(event.code)) {
    parts.push(chordLabelFor(event.code, keymapLabels))
  }
  return parts.join(" + ")
}

function parseFeed(raw) {
  var data = null
  try {
    data = JSON.parse(String(raw || ""))
  } catch (e) {
    return null
  }
  if (!data || typeof data !== "object") return null

  var down = []
  if (Array.isArray(data.down)) {
    for (var i = 0; i < data.down.length; i++) {
      var held = Number(data.down[i])
      if (isFinite(held) && held > 0 && Math.floor(held) === held) down.push(held)
    }
  }

  var mods = []
  if (Array.isArray(data.mods)) {
    for (var m = 0; m < data.mods.length; m++) {
      var mod = Number(data.mods[m])
      if (isFinite(mod) && mod > 0) mods.push(mod)
    }
  }

  var code = data.code === undefined || data.code === null ? null : Number(data.code)
  if (code !== null && (!isFinite(code) || code <= 0)) code = null

  return { t: Number(data.t) || 0, code: code, mods: mods, down: down }
}

function isDown(down, code) {
  var list = down || []
  for (var i = 0; i < list.length; i++) {
    if (list[i] === code) return true
  }
  return false
}

function pushEvent(history, event, limit, keymapLabels) {
  var max = limit && limit > 0 ? limit : 5
  var list = (history || []).slice()
  var text = chordText(event, keymapLabels)
  if (text === "") return list

  var last = list.length > 0 ? list[list.length - 1] : null
  if (last && last.text === text) {
    list[list.length - 1] = { text: text, count: last.count + 1, shownAt: last.shownAt }
    return list
  }

  list.push({ text: text, count: 1, shownAt: 0 })
  while (list.length > max) list.shift()
  return list
}

function stamp(history, nowMs) {
  var list = (history || []).slice()
  for (var i = 0; i < list.length; i++) {
    if (!list[i].shownAt) list[i] = { text: list[i].text, count: list[i].count, shownAt: nowMs }
  }
  return list
}

function expire(history, nowMs, lingerMs) {
  var linger = lingerMs && lingerMs > 0 ? lingerMs : 2000
  var out = []
  var list = history || []
  for (var i = 0; i < list.length; i++) {
    if (nowMs - list[i].shownAt < linger) out.push(list[i])
  }
  return out
}

function displayText(entry) {
  if (!entry) return ""
  return entry.count > 1 ? entry.text + "  x" + entry.count : entry.text
}

var STRIP_MODES = ["chords", "all", "off"]
// The three original values are the middle column of the grid, so they keep
// meaning exactly what they used to and an existing config needs no migration.
var POSITIONS = [
  "top-left", "top", "top-right",
  "left", "center", "right",
  "bottom-left", "bottom", "bottom-right"
]

var POSITION_PARTS = {
  "top-left": { vertical: "top", horizontal: "left" },
  "top": { vertical: "top", horizontal: "center" },
  "top-right": { vertical: "top", horizontal: "right" },
  "left": { vertical: "middle", horizontal: "left" },
  "center": { vertical: "middle", horizontal: "center" },
  "right": { vertical: "middle", horizontal: "right" },
  "bottom-left": { vertical: "bottom", horizontal: "left" },
  "bottom": { vertical: "bottom", horizontal: "center" },
  "bottom-right": { vertical: "bottom", horizontal: "right" }
}

function positionParts(value) {
  return POSITION_PARTS[normalizePosition(value)]
}

function positionVertical(value) {
  return positionParts(value).vertical
}

function positionHorizontal(value) {
  return positionParts(value).horizontal
}
var ORDERS = ["strip-above", "strip-below"]

function normalizeStrip(value) {
  var text = String(value || "chords").toLowerCase()
  return STRIP_MODES.indexOf(text) === -1 ? "chords" : text
}

function normalizePosition(value) {
  var text = String(value || "bottom").toLowerCase()
  return POSITIONS.indexOf(text) === -1 ? "bottom" : text
}

function normalizeOrder(value) {
  var text = String(value || "strip-above").toLowerCase()
  return ORDERS.indexOf(text) === -1 ? "strip-above" : text
}

function normalizeBool(value) {
  return value === true || value === "true" || value === 1 || value === "on"
}

function normalizeScale(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(0.5, Math.min(2, n))
}

function stripAbove(order) {
  return normalizeOrder(order) === "strip-above"
}

// The panel and the IPC change six of the ten settings. The other four are
// only ever set from the settings UI, so a patch has to merge into whatever is
// already stored rather than replace it, or turning the map off would silently
// reset someone's lingerMs and layout override.
function settingsWith(current, patch) {
  var entry = {}
  var key
  for (key in current) {
    if (key !== "id") entry[key] = current[key]
  }
  for (key in patch) {
    if (key !== "id") entry[key] = patch[key]
  }
  return entry
}

// Forcing qwerty is a first class choice rather than a layout override the
// user has to spell out, because "show it the way everyone else sees it" is
// the common case when demoing to other people.
var QWERTY_OVERRIDE = { layout: "us", variant: "" }

function overrideFrom(forceQwerty, layout, variant) {
  if (forceQwerty === true) return QWERTY_OVERRIDE
  var name = String(layout || "")
  if (name === "") return null
  return { layout: name, variant: String(variant || "") }
}

// Which keyboard the labels should follow. The main device is often a virtual
// keyboard belonging to an input method, which carries no variant, so a real
// device with a variant is the better answer when there is one.
function pickKeyboard(keyboards) {
  var list = keyboards || []
  var best = null
  for (var i = 0; i < list.length; i++) {
    var kb = list[i]
    if (!kb || !kb.name) continue
    if (String(kb.name).indexOf("hl-virtual-keyboard") === 0) continue
    if (kb.variant) return kb
    if (best === null) best = kb
  }
  if (best) return best
  return list.length > 0 ? list[0] : null
}

function keymapCommand(keyboard, override) {
  var layout = override && override.layout ? override.layout : (keyboard && keyboard.layout) || "us"
  var variant = override && override.variant !== undefined && override.variant !== null
    ? override.variant
    : (keyboard && keyboard.variant) || ""

  var command = ["xkbcli", "compile-keymap", "--layout", String(layout)]
  if (variant !== "") command.push("--variant", String(variant))
  return command
}

function layoutName(keyboard, override) {
  var layout = override && override.layout ? override.layout : (keyboard && keyboard.layout) || "us"
  var variant = override && override.variant !== undefined && override.variant !== null
    ? override.variant
    : (keyboard && keyboard.variant) || ""
  return variant === "" ? String(layout) : String(layout) + " " + String(variant)
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    LAYOUT: LAYOUT,
    ROW_UNITS: ROW_UNITS,
    MODIFIERS: MODIFIERS,
    MOD_ORDER: MOD_ORDER,
    CONTENT_FREE: CONTENT_FREE,
    STRIP_MODES: STRIP_MODES,
    POSITIONS: POSITIONS,
    ORDERS: ORDERS,
    labelForKeysym: labelForKeysym,
    parseKeymap: parseKeymap,
    labelFor: labelFor,
    chordLabelFor: chordLabelFor,
    rowUnits: rowUnits,
    keyCodes: keyCodes,
    isModifier: isModifier,
    isContentFree: isContentFree,
    modifierLabels: modifierLabels,
    chordText: chordText,
    parseFeed: parseFeed,
    isDown: isDown,
    pushEvent: pushEvent,
    stamp: stamp,
    expire: expire,
    displayText: displayText,
    normalizeStrip: normalizeStrip,
    normalizePosition: normalizePosition,
    positionParts: positionParts,
    positionVertical: positionVertical,
    positionHorizontal: positionHorizontal,
    normalizeOrder: normalizeOrder,
    normalizeBool: normalizeBool,
    normalizeScale: normalizeScale,
    stripAbove: stripAbove,
    settingsWith: settingsWith,
    QWERTY_OVERRIDE: QWERTY_OVERRIDE,
    overrideFrom: overrideFrom,
    pickKeyboard: pickKeyboard,
    keymapCommand: keymapCommand,
    layoutName: layoutName
  }
}
