-- @description AKAI MidiMix for REAPER
-- @version 0.29
-- @author The Eighth
-- @link GitHub https://github.com/eighthkeepa/AKAI-MidiMix-for-REAPER
-- @about
--   Akai MidiMix as a full REAPER controller in one ReaScript (no ReaLearn, OSC or extensions):
--   banks, faders, pan, width, sends, mute/solo/rec, LEDs, instrument mode, a ReaImGui window.
--   The window needs ReaImGui (optional).
-- @provides
--   [nomain] midimix/*.lua
-- @changelog
--   0.29: the color highlight animation is back as an opt-in "Fill animation" setting (off by default): on start the bank fills strip by strip during the LED circle, on exit the tint follows the blink phases
--   0.28: removed the animated color highlight; the color tint is instant again (as in 0.26)
--   0.26: device scan every second, so the window notices an unplug within about 1 s; how fast REAPER itself notices the unplug can still vary by system
--   0.25: the window notices an unplugged MidiMix within about 2 seconds (was 5)
--   0.24: REAPER no longer freezes when the script exits: the exit blink now runs in the background; exit cleanup (bank highlight, LEDs, toolbar button) verified by tests
--   0.23: softer, a bit brighter 0 dB line; Help tab and hover hints; second mixer look in the style of the Akai MPC 2.0; Russian window (Settings > Window); settings group "Window"
--   0.22: renamed to "AKAI MidiMix" (file, window, ReaPack); master mute / solo / pan (hold Bank Right); Bank hold jumps on release; double tap Solo restores the exact solo state; restart hint on collapsed Settings groups
--   0.21: width knob only works on tracks in stereo pan mode; the script no longer switches pan mode on its own (opt-in setting); window title in Akai Red; window never docks; Settings tab uses collapsible groups
--   0.20: window shows the master fader; fader scale follows the fader top; meters follow pan; fader top is +12 dB by default
--   0.19: mixer window redesigned in the style of the Akai MPC mixer, level meters, strip frames, modules in midimix/

--[[
  AKAI MidiMix for REAPER - version 0.29

  Not verified on every setup. If something is off, run AKAI MidiMix probe.lua first:
  it shows which notes and CCs your MidiMix actually sends.

  Features:
    * a bank of 8 tracks, Bank Left / Bank Right buttons
    * faders = track volume, master fader = master volume
    * bottom knob row = pan, middle row = width (stereo pan), top row = sends
    * Mute and Rec arm for every track
    * Solo (hold) + Mute N = solo that track; Solo tap = solo the whole bank
    * Solo + Rec = rec arm the whole bank; Solo + Bank = shift the bank by 1 track
    * both Bank buttons together = switch the whole bank to stereo pan
    * Send All tap = next send; Send All hold ~1 s = controller on/off
    * soft takeover (pickup) for knobs and faders
    * LEDs and a window (needs ReaImGui; without it everything works, just no window)
    * spacers above and below the bank

  Your own settings: put a midimix_config.lua file next to this script. It must
  return a table, for example:   return { bank_size = 6, highlight = "none" }

  Copyright (c) 2026 The Eighth. Licensed under the GNU GPL v3 or later (see LICENSE).
]]

-- Shared environment: all modules see the same names (CFG, S, helpers).
local R = reaper
local function dir_of(path) return path and path:match("^(.*)[/\\][^/\\]*$") end
local function readable(path) local f = io.open(path, "r"); if f then f:close() return true end return false end
local dir
do
  local src = debug and debug.getinfo and debug.getinfo(1, "S").source or ""
  dir = dir_of(src:sub(1, 1) == "@" and src:sub(2) or src) or "."
  if not readable(dir .. "/midimix/settings.lua") then
    local _, sp = R.get_action_context()
    dir = dir_of(sp) or dir
  end
end
local ENV = setmetatable({}, { __index = _G })
ENV.R = R
ENV.MODULE_DIR = dir .. "/midimix"
for _, name in ipairs({ "settings", "lang", "device", "tracks", "instrument", "input", "gui", "highlight" }) do
  local path = ENV.MODULE_DIR .. "/" .. name .. ".lua"
  local chunk, err = loadfile(path, "t", ENV)
  if not chunk then
    R.ShowConsoleMsg("[MidiMix] cannot load module " .. name .. ": " .. tostring(err) .. "\n")
    return
  end
  chunk()
end
local _ENV = ENV

local function tick()
  local now = R.time_precise()
  if not strips_valid() then rebuild(now) end  -- a track was deleted: rebuild the bank right away
  if now - S.last_scan > 1 then scan_devices(now) end
  poll_midi(now)

  if S.sa_down and not S.sa_trig and now - S.sa_t >= CFG.hold_s then
    S.sa_trig = true
    toggle_enabled("Send All hold")
  end
  if S.pending_page_at and now >= S.pending_page_at then
    S.pending_page_at = nil
    sendall_short()
  end

  if now - S.last_rebuild > 0.1 then rebuild(now) end
  follow_mixer_scroll(now)
  check_external()
  update_markers(now)
  update_colors(now)
  learn_tick(now)
  if now - (S.proj_poll or 0) > 1 then S.proj_poll = now; reload_binds_if_project_changed() end
  if S.sp_dirty then update_spacers() end
  update_leds(now)
end

-- Exit blink, deferred: the Mute and Rec rows blink twice across normal tick
-- callbacks, so REAPER never blocks. Returns true when the blink is over.
local function exit_tick(now)
  if not CFG.exit_blink or S.out_idx == nil or not S.device_ok then return true end
  local m, notes = CFG.map, {}
  for i = 1, 8 do notes[#notes + 1] = m.mute[i]; notes[#notes + 1] = m.rec[i] end
  if not S.exit_t then S.exit_t = now end
  local step = math.floor((now - S.exit_t) / math.min(CFG.exit_blink_s, 0.25))
  S.exit_step = step
  if step >= 4 then return true end
  local on = step % 2 == 0
  for _, n in ipairs(notes) do led_set(n, on, true) end
  return false
end

-- With "Fill animation" on, the color highlight follows the exit blink: the
-- bank is tinted while the LED rows are lit and in original colours while
-- they are dark. cleanup() restores everything for good afterwards.
local function exit_colors(now)
  if not CFG.fill_anim or CFG.highlight ~= "color" or not S.enabled or S.exit_step == nil then return end
  local want = {}
  if S.exit_step % 2 == 0 then
    for i = 1, CFG.bank_size do
      local tr = S.strips[i]
      if tr then want[guid(tr)] = tr end
    end
  end
  update_colors(now, want)
end

-- Everything temporary is undone: bank highlight, LEDs, toolbar button state.
-- Safe to run twice (atexit runs it again after the deferred quit finishes).
local function cleanup()
  S.enabled = false
  pcall(update_markers, R.time_precise())
  pcall(update_colors, R.time_precise())
  pcall(update_spacers)
  pcall(function()
    for _, note in ipairs(led_notes) do led_set(note, false, true) end
  end)
  if SEC and CMD and CMD ~= 0 then
    R.SetToggleCommandState(SEC, CMD, 0)
    R.RefreshToolbar2(SEC, CMD)
  end
end

local function loop()
  if S.quit then
    -- quitting: blink on defer ticks, then clean up and stop the defer chain
    local now = R.time_precise()
    local done = true
    pcall(function() done = exit_tick(now) end)
    if done then
      cleanup()
    else
      pcall(exit_colors, now)   -- the tint follows the blink phases (Fill animation on)
      R.defer(loop)
    end
    return
  end
  local ok, err = pcall(tick)
  if not ok then report_error("logic", err) end
  local ok2, err2 = pcall(draw_gui)
  if not ok2 then report_error("window", err2) end
  R.defer(loop)
end

load_binds()
cleanup_stale_spacers()
scan_devices(R.time_precise())
if not S.device_ok then say("MidiMix not found. Plug it in and enable its input and output in Preferences > MIDI Devices.") end
set_toolbar()
R.atexit(cleanup)
loop()
