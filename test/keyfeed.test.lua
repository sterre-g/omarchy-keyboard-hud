-- Checks on keyfeed.lua, the half of the plugin that Hyprland calls with every
-- keypress. The interesting properties are not what it draws but what it
-- refuses to do: subscribe before it is asked to, open a path someone else can
-- replace, or write through a symlink.
--
-- Run through ./run-tests, which points XDG_RUNTIME_DIR at a scratch directory.

local runtime = assert(os.getenv("XDG_RUNTIME_DIR"), "XDG_RUNTIME_DIR must be set")
local state_dir = runtime .. "/sterre-keyboard-hud"
local feed = state_dir .. "/feed.json"
local victim = runtime .. "/victim"

local passed = 0
local function ok(cond, what)
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
  passed = passed + 1
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function shell(cmd)
  os.execute(cmd)
end

-- A stand in for the Hyprland API, recording what the script subscribes to.
local subscribed = 0
local removed = 0
local callback = nil
_G.hl = {
  on = function(event, cb)
    ok(event == "input.keyboard.key", "subscribes to the key event")
    subscribed = subscribed + 1
    callback = cb
    return { remove = function() removed = removed + 1; callback = nil end }
  end,
}

dofile("keyfeed.lua")

-- Loading alone must not put a keystroke subscription in place. Until the bar
-- widget says otherwise Hyprland is not handing this script anything.
ok(subscribed == 0, "loading the script subscribes to nothing")
ok(callback == nil, "no callback is live before a config push")

-- The source must not name a config path at all. Reading one on the key path is
-- what let a fifo block Hyprland's input callback.
local source = assert(read("keyfeed.lua"))
ok(not source:find("%.conf"), "the script names no config file")
ok(not source:find('io%.open%(feed_path'), "the script never opens the feed path directly")

-- /tmp is shared with every other account on the machine. A keystroke feed
-- that lands there because XDG_RUNTIME_DIR happened to be unset is the finding,
-- so the fallback must not exist in the source at all.
ok(not source:find('"/tmp"'), "there is no /tmp fallback")

-- The directory is the security argument for the fixed staging name, so it has
-- to actually be private and actually be a directory.
local mode = io.popen("stat -c '%a %F' " .. state_dir):read("*a")
ok(mode:match("^700 directory"), "the state directory is a private directory, got " .. mode)

-- Predictable PRNG naming was doing no work the directory was not already
-- doing, and remove-then-open is a window rather than a guarantee.
ok(not source:find("math%.random%("), "the staging name does not come from math.random")
ok(not source:find("os%.remove%(tmp%)"), "the staging file is not removed before it is opened")

-- Panel.qml reaches the setter by evaluating this exact text through
-- `hyprctl eval`, so a rename on either side has to fail here rather than
-- quietly leave the HUD installed and drawing nothing.
local call = assert(load('__sterre_keyboard_hud_config("chords", true)'))
call()
ok(subscribed == 1, "the string Panel.qml evals reaches the setter")
__sterre_keyboard_hud_config("off", false)
ok(removed == 1, "and off again puts the subscription back")
subscribed, removed = 0, 0

-- Off stays off.
__sterre_keyboard_hud_config("off", false)
ok(subscribed == 0, "an off push subscribes to nothing")

-- Anything unrecognised is off, not a mode that records.
__sterre_keyboard_hud_config("everything", false)
ok(subscribed == 0, "an unknown strip mode is treated as off")
__sterre_keyboard_hud_config(nil, nil)
ok(subscribed == 0, "a malformed push is treated as off")

-- Turning the strip on subscribes exactly once.
__sterre_keyboard_hud_config("chords", false)
ok(subscribed == 1, "turning the strip on subscribes once")
__sterre_keyboard_hud_config("chords", true)
ok(subscribed == 1, "a second push does not subscribe again")

-- In chords mode a plain letter with no modifier held is dropped, and only the
-- held set reaches the feed.
os.remove(feed)
callback(38, 1000, 1) -- 'a' on a us board
local payload = assert(read(feed), "the feed is written")
ok(not payload:find('"code"'), "chords mode drops a plain letter")
ok(payload:find('"down":%[38%]'), "the map still reports the held key")
callback(38, 1001, 0)

-- With a modifier held the chord is recorded.
callback(37, 1002, 1) -- Ctrl
callback(38, 1003, 1) -- Ctrl+a
payload = assert(read(feed))
ok(payload:find('"code":38'), "a chord is recorded")
ok(payload:find('"mods":%[37%]'), "the modifier is reported with it")
callback(38, 1004, 0)
callback(37, 1005, 0)

-- In all mode the same plain letter is recorded.
__sterre_keyboard_hud_config("all", false)
callback(38, 1006, 1)
payload = assert(read(feed))
ok(payload:find('"code":38'), "all mode records a plain letter")
ok(not payload:find('"down"'), "the held set is withheld while the map is off")
callback(38, 1007, 0)

-- The write must not follow a symlink planted where the feed goes. This is the
-- finding: opening that path with "w" truncates whatever it points at.
os.remove(feed)
local v = assert(io.open(victim, "w"))
v:write("PRECIOUS")
v:close()
shell("ln -sf " .. victim .. " " .. feed)
callback(38, 1008, 1)
ok(read(victim) == "PRECIOUS", "a symlink at the feed path is not written through")
payload = assert(read(feed))
ok(payload:find('"code":38'), "the feed is written anyway")
shell("test -L " .. feed .. " && exit 1 || exit 0")
callback(38, 1009, 0)

-- No temporary files are left behind.
local leftovers = io.popen("ls " .. state_dir .. " | grep -c '%.tmp$' || true"):read("*a")
ok(tonumber(leftovers) == 0 or leftovers:match("^0"), "no staging files are left behind")

-- Turning everything off unsubscribes rather than merely staying quiet, and
-- clears the feed without following a link planted in its place.
os.remove(feed)
shell("ln -sf " .. victim .. " " .. feed)
__sterre_keyboard_hud_config("off", false)
ok(removed == 1, "turning the HUD off removes the subscription")
ok(read(victim) == "PRECIOUS", "clearing the feed does not delete through a symlink")

print(passed .. " assertions passed (keyfeed.lua)")
