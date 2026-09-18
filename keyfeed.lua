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

-- Everything this plugin writes lives in a directory of its own, mode 0700,
-- inside XDG_RUNTIME_DIR. That directory is the entire security argument for
-- the writes further down: no other user can create a name inside it, so there
-- is no symlink to follow, no name to plant, and a fixed staging name is worth
-- exactly as much as a random one. Lua's io.open cannot ask for O_EXCL or
-- O_NOFOLLOW, so the guarantee has to come from the directory rather than from
-- the open, and it is established once here, never on the key path.
--
-- There is deliberately no /tmp fallback. /tmp is shared, and a keystroke feed
-- is not something to write somewhere every account on the box can reach; with
-- no XDG_RUNTIME_DIR the feed stays off and the subscription is never made.
local runtime_dir = os.getenv("XDG_RUNTIME_DIR")
local state_dir = runtime_dir and (runtime_dir .. "/sterre-keyboard-hud") or nil
local feed_path = state_dir and (state_dir .. "/feed.json") or nil
local tmp_path = feed_path and (feed_path .. ".tmp") or nil

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- os.execute returns true on Lua 5.2+ and the raw exit status on 5.1.
local function shell_ok(command)
  local ok, _, code = os.execute(command)
  return ok == true or ok == 0 or (ok and code == 0)
end

-- mkdir -m 700 creates it with the mode already in place, so it never exists
-- readable by anyone else even briefly. The tests then refuse a directory that
-- was there first and belongs to somebody else, or a symlink left in its place;
-- chmod re-tightens one of ours that an earlier version left too open.
local function state_dir_ready()
  if not state_dir then return false end
  local quoted = shell_quote(state_dir)
  return shell_ok(table.concat({
    "mkdir -m 700 -p ", quoted, " 2>/dev/null",
    " && [ ! -L ", quoted, " ]",
    " && [ -d ", quoted, " ]",
    " && [ -O ", quoted, " ]",
    " && chmod 700 ", quoted, " 2>/dev/null",
  }))
end

local writable = state_dir_ready()

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

-- Staged and renamed rather than written in place, so a reader never sees half
-- a record. The staging name is fixed because it sits in a directory only this
-- user can write; the old code drew it from math.random, which is a predictable
-- PRNG and was doing no work the directory was not already doing.
local function write_feed(time_ms, code, want_map)
  local file = io.open(tmp_path, "w")
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

  if not os.rename(tmp_path, feed_path) then os.remove(tmp_path) end
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
  if subscription or not writable then return end
  held = {}
  subscription = hl.on("input.keyboard.key", on_key)
end

local function stop()
  if subscription then
    subscription:remove()
    subscription = nil
  end
  held = {}
  if feed_path then os.remove(feed_path) end
  if tmp_path then os.remove(tmp_path) end
end

-- Called by the bar widget through `hyprctl eval`. Anything that is not one of
-- the two recording modes is off, so a malformed push cannot switch recording
-- on by accident.
function _G.__sterre_keyboard_hud_config(strip, map)
  strip_mode = (strip == "all" or strip == "chords") and strip or "off"
  map_on = map == true

  if strip_mode ~= "off" or map_on then start() else stop() end
  return writable and "ok" or "no private runtime directory, feed disabled"
end

if feed_path then os.remove(feed_path) end
if tmp_path then os.remove(tmp_path) end
