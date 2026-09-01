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
--
-- Nothing here reads a file. The two settings that decide what may be recorded
-- are pushed in by the bar widget through hyprctl eval, so no path that another
-- process can replace is ever opened on the key path. A callback that opened
-- one would be a callback that can be made to block on a fifo or to read a file
-- grown without bound, and it runs on the thread that delivers input.
--
-- While both halves are off there is no subscription at all, so Hyprland is not
-- handing this script keystrokes in the first place. Turning the HUD off is
-- unsubscribing, not declining to draw.

-- hyprctl reload re-runs the config and with it this file, so without a guard
-- each reload would add another subscription writing the same feed.
if _G.__sterre_keyboard_hud_loaded then return end
_G.__sterre_keyboard_hud_loaded = true

local runtime_dir = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local feed_path = runtime_dir .. "/sterre-keyboard-hud.json"

-- Names the feed is staged under before it is renamed into place. Fresh per
-- write and unpredictable, so there is no name to plant anything at.
math.randomseed()
local seq = 0

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

-- Off until the bar widget says otherwise. XDG_RUNTIME_DIR is wiped at logout
-- and this state does not outlive Hyprland, so the default has to be the one
-- that records nothing: between Hyprland loading this script and the shell
-- coming up there is nobody to ask, and the HUD has nothing to draw on anyway.
local strip_mode = "off"
local map_on = false
local subscription = nil

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

-- Atomic, and safe against a symlink planted at feed_path. The payload is
-- written to a private name and renamed over the target: rename replaces
-- whatever sits there, and replacing a symlink unlinks the link rather than
-- writing through it. Opening feed_path with "w" instead, which is what this
-- used to do, truncates and writes into whatever the link points at.
local function write_feed(time_ms, code, want_map)
  seq = seq + 1
  local tmp = string.format("%s.%d.%d.tmp", feed_path, seq, math.random(0, 2 ^ 30))
  os.remove(tmp)

  local file = io.open(tmp, "w")
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

  if not os.rename(tmp, feed_path) then os.remove(tmp) end
end

local function on_key(keycode, time_ms, state)
  if state == 1 then
    held[keycode] = true
  elseif state == 0 then
    held[keycode] = nil
  else
    return
  end

  local code = nil
  if state == 1 and strip_mode ~= "off" and not MODIFIERS[keycode] then
    if strip_mode == "all" or CONTENT_FREE[keycode] or #modifiers_held() > 0 then
      code = keycode
    end
  end

  write_feed(time_ms, code, map_on)
end

local function start()
  if subscription then return end
  held = {}
  subscription = hl.on("input.keyboard.key", on_key)
end

local function stop()
  if subscription then
    subscription:remove()
    subscription = nil
  end
  held = {}
  -- Unlinking follows no symlink, so this clears the feed and never the target
  -- of one planted in its place.
  os.remove(feed_path)
end

-- Called by the bar widget through `hyprctl eval`. Anything that is not one of
-- the two recording modes is off, so a malformed push cannot switch recording
-- on by accident.
function _G.__sterre_keyboard_hud_config(strip, map)
  strip_mode = (strip == "all" or strip == "chords") and strip or "off"
  map_on = map == true

  if strip_mode ~= "off" or map_on then start() else stop() end
end

os.remove(feed_path)
