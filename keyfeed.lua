-- Key feed for sterre.keyboard-hud.
--
-- Hyprland hands this callback every keypress from every window, so this file
-- is where it is decided what is allowed to reach the disk at all. Both halves
-- of the HUD are gated separately:
--
--   the strip needs the chord that was just pressed
--   the map needs the set of keys held right now
--
-- With the strip in its default "chords" mode, a plain character key with no
-- modifier held is dropped here and never written anywhere. With the map off,
-- the held set is not written either. Only keycodes are ever written, never
-- characters, and only into XDG_RUNTIME_DIR, which systemd creates as mode
-- 0700 and wipes on logout.

-- hyprctl reload re-runs the config and with it this file, so without a guard
-- each reload would add another subscription writing the same feed.
if _G.__sterre_keyboard_hud_loaded then return end
_G.__sterre_keyboard_hud_loaded = true

local runtime_dir = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local feed_path = runtime_dir .. "/sterre-keyboard-hud.json"
local conf_path = runtime_dir .. "/sterre-keyboard-hud.conf"

-- X11 keycodes: the evdev code plus 8.
local MODIFIERS = {
  [37] = true, [105] = true,  -- Ctrl
  [50] = true, [62] = true,   -- Shift
  [64] = true, [108] = true,  -- Alt
  [133] = true, [134] = true, -- Super
}

-- Keys that carry no typed text, so the strip may show them in chords mode
-- even with no modifier held.
local CONTENT_FREE = {
  [9] = true, [22] = true, [23] = true, [36] = true, [66] = true,
  [67] = true, [68] = true, [69] = true, [70] = true, [71] = true, [72] = true,
  [73] = true, [74] = true, [75] = true, [76] = true, [95] = true, [96] = true,
  [107] = true,
  [110] = true, [111] = true, [112] = true, [113] = true, [114] = true,
  [115] = true, [116] = true, [117] = true, [118] = true, [119] = true,
  [121] = true, [122] = true, [123] = true, [135] = true,
  [171] = true, [172] = true, [173] = true, [174] = true,
}

local held = {}

-- The bar widget writes this file. Lua has no json parser and needs only the
-- two fields that decide what may be recorded.
local function read_conf()
  local file = io.open(conf_path, "r")
  if not file then return "chords", false end
  local text = file:read("*a") or ""
  file:close()

  local strip = text:match('"strip"%s*:%s*"(%a+)"')
  if strip ~= "all" and strip ~= "off" then strip = "chords" end
  local map = text:match('"map"%s*:%s*true') ~= nil
  return strip, map
end

local function sorted_held()
  local codes = {}
  for code in pairs(held) do
    codes[#codes + 1] = code
  end
  table.sort(codes)
  return codes
end

local function join(codes)
  local parts = {}
  for i = 1, #codes do
    parts[i] = tostring(codes[i])
  end
  return table.concat(parts, ",")
end

local function modifiers_held()
  local codes = {}
  for code in pairs(held) do
    if MODIFIERS[code] then codes[#codes + 1] = code end
  end
  table.sort(codes)
  return codes
end

local function write_feed(time_ms, code, want_map)
  local file = io.open(feed_path, "w")
  if not file then return end

  local parts = { '"t":' .. tostring(time_ms) }
  if code then
    parts[#parts + 1] = '"code":' .. tostring(code)
    parts[#parts + 1] = '"mods":[' .. join(modifiers_held()) .. "]"
  end
  if want_map then
    parts[#parts + 1] = '"down":[' .. join(sorted_held()) .. "]"
  end

  file:write("{" .. table.concat(parts, ",") .. "}")
  file:close()
end

hl.on("input.keyboard.key", function(keycode, time_ms, state)
  local strip, map = read_conf()

  if strip == "off" and not map then
    if next(held) ~= nil then
      held = {}
      write_feed(time_ms, nil, false)
    end
    return
  end

  if state == 1 then
    held[keycode] = true
  elseif state == 0 then
    held[keycode] = nil
  else
    return
  end

  local code = nil
  if state == 1 and strip ~= "off" and not MODIFIERS[keycode] then
    if strip == "all" or CONTENT_FREE[keycode] or #modifiers_held() > 0 then
      code = keycode
    end
  end

  write_feed(time_ms, code, map)
end)
