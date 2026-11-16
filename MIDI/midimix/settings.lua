-- @noindex
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (c) 2026 The Eighth
-- MidiMix module: Settings, config file, helpers, shared state. Loaded by AKAI MidiMix.lua into a shared environment.
-- Top-level names here are shared between modules (the 'local' keyword is dropped on purpose).

R = reaper

---------------------------------------------------------------------------
-- SETTINGS (can be overridden in midimix_config.lua)
---------------------------------------------------------------------------
CFG = {
  device_match = "midi%s*mix", -- part of the device name (Lua pattern, case-insensitive)
  midi_channel = 0,            -- 0 = channel 1; nil = any channel
  bank_size = 8,               -- 1..8
  mixer_visible_only = true,   -- only count tracks that are visible in the mixer
  hold_s = 1.0,                -- how long to hold Send All for on/off
  bank_hold_s = 0.5,           -- hold Bank Left / Right this long = jump to the first / last bank
  pickup_window = 3,           -- pickup: tolerance in steps 0..127
  center_snap = 2,             -- pan and width: snap to center, steps 0..127
  width_needs_stereo_pan = true, -- the width knob only works on tracks whose pan mode is "stereo pan" (otherwise width does nothing audible)
  allow_panmode_change = false,  -- true: Solo + middle knob and both Bank buttons switch tracks to stereo pan (changes the project!)
  fader_max_db = 12,           -- top of the fader, dB (REAPER and the MIDI Mix go up to +12)
  solo_value = 2,              -- value written to I_SOLO: 1 = solo, 2 = solo in place
  highlight = "spacers",       -- how the bank is shown in the track list / mixer:
                               --   "spacers" = spacer above and below the bank
                               --   "markers" = two red separator tracks "MidiMix" around the bank (inserted while the script runs)
                               --   "color"   = the bank's tracks are tinted red (original colours are restored)
                               --   "none"
  highlight_tint = 0.45,       -- "color" mode: how much red is mixed in, 0..1
  marker_color = {0xBC, 0x01, 0x2E},  -- Akai Red
  rec_modes = true,            -- double tap Solo cycles what the Rec row does: arm -> send mute -> FX bypass
  follow_mixer = false,        -- true: scrolling the mixer by hand moves the bank to the first visible track
  scroll_mixer = true,         -- scroll the mixer to the start of the bank
  sends_by_name = false,       -- true: match sends by destination track name
  page_flash_s = 1.2,          -- how long the Rec LEDs show the send page number
  blink_hz = 2,                -- solo blink rate
  led_refresh_s = 5,           -- how often to resend the LED state
  window = true,               -- draw the window (if ReaImGui is installed)
  language = "en",             -- window language: "en" or "ru"
  mixer_style = "classic",     -- window mixer look: "classic" (bars) or "mpc" (round knobs, like the Akai MPC 2.0 mixer)
  tooltips = true,             -- short hints when the mouse rests on a part of a strip
  track_sends = true,          -- hold Rec N + tap Send All = next send of that track only
  global_sends = false,        -- true: a plain Send All tap switches the send of ALL tracks in the bank
  meter_after_pan = true,      -- meters follow pan: the far side gets quieter (balance law)
  meter_after_fader = true,    -- multiply the meter by the fader (the REAPER API gives the level before the fader)
  startup_anim = true,         -- LED circle when the script starts / device appears
  startup_step_s = 0.07,       -- time per LED step of that circle
  exit_blink = true,           -- Mute and Rec rows blink twice when the script stops
  exit_blink_s = 0.18,         -- length of one on / off phase of that blink
  bank_blink_base_hz = 1,      -- Bank Right LED blink rate on the 2nd bank
  bank_blink_step_hz = 1,      -- ... plus this much for every further bank
  bank_blink_max_hz = 8,       -- ... but not faster than this
  solo_leds_on_mute = false,   -- true: while Solo is held, show solo state on the Mute LEDs yourself (old behaviour)
  skip_separators = false,     -- true: separator tracks are not counted in the bank at all (false: they take a dead slot)
  separator_names = {          -- an EMPTY track (no items, FX, sends) whose name matches one of these is a separator
    "^%s*[%-=_#%*~|]",         -- starts with - = _ # * ~ |
    "separator", "midimix", "разделитель", "Разделитель",
  },
  separator_max_h = 30,        -- an EMPTY track whose height was set by hand (I_HEIGHTOVERRIDE) to at most this many px is a separator; 0 = off
  debug = false,               -- write events to midimix_log.txt (resource folder)

  -- If Send All sends its own note, put it here (the probe script tells you).
  -- If nil, Send All is detected by its CC "dump" (a burst of CCs), and then:
  --   tap = next send, double tap = on/off.
  send_all_note = nil,
  burst_min = 20,              -- how many different CCs within burst_window count as a dump
  burst_window = 0.15,
  double_tap_s = 0.5,

  -- Factory MidiMix layout (channel 1). Verify with the probe script.
  map = {
    fader    = {19, 23, 27, 31, 49, 53, 57, 61},
    master   = 62,
    knob_top = {16, 20, 24, 28, 46, 50, 54, 58},
    knob_mid = {17, 21, 25, 29, 47, 51, 55, 59},
    knob_bot = {18, 22, 26, 30, 48, 52, 56, 60},
    mute     = {1, 4, 7, 10, 13, 16, 19, 22},
    rec      = {3, 6, 9, 12, 15, 18, 21, 24},
    solo_strip = {2, 5, 8, 11, 14, 17, 20, 23}, -- notes Mute most likely sends while Solo is held
    bank_left = 25, bank_right = 26, solo = 27,
  },
}

_, SCRIPT_PATH, SEC, CMD = R.get_action_context()

function is_array(t) return type(t) == "table" and t[1] ~= nil end
function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" and not is_array(v) then
      merge(dst[k], v)
    else
      dst[k] = v
    end
  end
end

function say(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  R.ShowConsoleMsg("[MidiMix] " .. table.concat(parts, " ") .. "\n")
end
function dbg(...)
  if not CFG.debug then return end
  if not LOG_F then LOG_F = io.open(R.GetResourcePath() .. "/midimix_log.txt", "a") end
  if not LOG_F then return end
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  LOG_F:write(string.format("%.3f ", R.time_precise()) .. table.concat(parts, " ") .. "\n")
  LOG_F:flush()
end

do
  local dir = SCRIPT_PATH and SCRIPT_PATH:match("^(.*)[/\\][^/\\]*$")
  if dir then
    local p = dir .. "/midimix_config.lua"
    local f = io.open(p, "r")
    if f then
      f:close()
      local ok, res = pcall(dofile, p)
      if ok and type(res) == "table" then
        merge(CFG, res)
        -- old config keys
        if res.highlight == nil then
          if res.marker_track then CFG.highlight = "markers"
          elseif res.spacers == false then CFG.highlight = "none" end
        end
      else say("error in midimix_config.lua:", res) end
    end
  end
end

CFG.bank_size = math.max(1, math.min(8, math.floor(CFG.bank_size)))
-- values from midimix_config.lua: keep the timings in a sensible range
for key, lo, hi in ([[hold_s 0.3 5  bank_hold_s 0.2 2  double_tap_s 0.2 1  burst_window 0.05 1  burst_min 5 33
  exit_blink_s 0.02 0.25  startup_step_s 0.02 0.5  led_refresh_s 1 60]]):gmatch("(%S+)%s+(%S+)%s+(%S+)") do
  local v = tonumber(CFG[key])
  if v then CFG[key] = math.max(tonumber(lo), math.min(tonumber(hi), v)) end
end

---------------------------------------------------------------------------
-- SETTINGS SCREEN: schema + persistence (REAPER ExtState)
-- Priority: defaults < midimix_config.lua < values saved from the window.
---------------------------------------------------------------------------
SET_SEC = "MidiMixLua_settings"
SCHEMA = {
  { group = "Window" },
  { key = "language", label = "Language", kind = "enum", live = false, tip = "Window language. Needs a restart.",
    options = { "en", "ru" }, names = { "English", "Русский" } },
  { key = "mixer_style", label = "Mixer look", kind = "enum", live = true,
    options = { "classic", "mpc" }, names = { "Classic (bars)", "MPC 2.0 (round knobs)" } },
  { key = "tooltips", label = "Hover hints", kind = "bool", live = true,
    tip = "Show a short hint when the mouse rests on part of a strip." },
  { group = "Knobs and faders" },
  { key = "pickup_window", label = "Pickup tolerance", kind = "int", min = 0, max = 20, live = true,
    tip = "0 means no tolerance. A bigger value makes it easier to catch the current value (steps 0 to 127)." },
  { key = "center_snap", label = "Pan centre snap", kind = "int", min = 0, max = 10, live = true },
  { key = "fader_max_db", label = "Fader top, dB", kind = "float", min = 0, max = 12, live = true },
  { key = "width_needs_stereo_pan", label = "Width knob only on tracks in stereo pan mode", kind = "bool", live = true,
    tip = "On: the width knob skips tracks in other pan modes, where width would not be audible." },
  { key = "allow_panmode_change", label = "Allow switching tracks to stereo pan from the device", kind = "bool", live = true,
    tip = "Off by default, so the script never changes a track's pan mode. When on, Solo + middle knob and both Bank buttons switch tracks to stereo pan." },
  { group = "Sends" },
  { key = "track_sends", label = "Rec N + Send All = next send of one track", kind = "bool", live = true },
  { key = "global_sends", label = "Send All tap = next send of ALL tracks", kind = "bool", live = true },
  { key = "sends_by_name", label = "Match sends by name", kind = "bool", live = false },
  { group = "Mixer" },
  { key = "bank_size", label = "Tracks in a bank", kind = "int", min = 1, max = 8, live = false },
  { key = "skip_separators", label = "Skip separator tracks (no dead slot)", kind = "bool", live = true },
  { key = "separator_max_h", label = "Separator height up to, px (0 = off)", kind = "int", min = 0, max = 80, live = true,
    tip = "An empty track whose height you set by hand to at most this is treated as a separator." },
  { key = "highlight", label = "Show the bank with", kind = "enum", live = true,
    options = { "spacers", "markers", "color", "none" },
    names = { "Spacers", "Two red MidiMix separator tracks", "Tint the tracks red", "Nothing" } },
  { key = "highlight_tint", label = "Tint strength", kind = "float", min = 0.1, max = 0.9, live = true },
  { key = "rec_modes", label = "Double tap Solo switches the Rec row mode", kind = "bool", live = true },
  { key = "follow_mixer", label = "Bank follows mixer scroll", kind = "bool", live = true },
  { key = "scroll_mixer", label = "Scroll mixer to the bank", kind = "bool", live = true },
  { group = "LEDs and animations" },
  { key = "meter_after_fader", label = "Meters show level after the fader", kind = "bool", live = true },
  { key = "meter_after_pan", label = "Meters follow pan (left/right levels)", kind = "bool", live = true },
  { key = "startup_anim", label = "LED circle on start", kind = "bool", live = true },
  { key = "exit_blink", label = "Double blink on exit", kind = "bool", live = true },
  { key = "blink_hz", label = "Solo blink, Hz", kind = "float", min = 0.5, max = 8, live = true },
  { key = "bank_blink_max_hz", label = "Bank blink, max Hz", kind = "float", min = 1, max = 12, live = true },
  { key = "page_flash_s", label = "Send number on LEDs, s", kind = "float", min = 0, max = 3, live = true },
  { group = "Other" },
  { key = "bank_hold_s", label = "Hold Bank = first/last bank, s", kind = "float", min = 0.2, max = 2, live = true },
  { key = "double_tap_s", label = "Double tap time, s", kind = "float", min = 0.2, max = 1, live = true },
  { key = "debug", label = "Debug log (midimix_log.txt)", kind = "bool", live = true },
}
BASE, SHOWN = {}, {}   -- BASE: value without saved overrides; SHOWN: value the window shows

function parse_setting(item, str)
  if str == nil or str == "" then return nil end
  if item.kind == "bool" then
    if str == "true" then return true elseif str == "false" then return false end
    return nil
  end
  if item.kind == "enum" then
    for _, o in ipairs(item.options) do if o == str then return str end end
    return nil
  end
  local v = tonumber(str)
  if not v then return nil end
  if item.kind == "int" then v = math.floor(v + 0.5) end
  return math.max(item.min, math.min(item.max, v))
end

for _, item in ipairs(SCHEMA) do
  if item.key then
    BASE[item.key] = CFG[item.key]
    local v = parse_setting(item, R.GetExtState(SET_SEC, item.key))
    if v ~= nil then CFG[item.key] = v end
    SHOWN[item.key] = CFG[item.key]
  end
end


---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
S = {
  enabled = true,
  first = 1, anchor_guid = nil, vis = {}, nvis = 0, strips = {}, sig = "",
  in_idx = {}, out_idx = nil, last_scan = -100, device_ok = false,
  last_seq = nil,
  phys = {}, picked = {}, last = {}, key_info = {},
  solo_held = false, solo_used = false,
  bank_t = { [-1] = 0, [1] = 0 },
  bank_down = { [-1] = false, [1] = false }, bank_used = { [-1] = false, [1] = false },
  sa_down = false, sa_t = 0, sa_trig = false,
  burst_t0 = -100, burst_seen = {}, burst_cnt = 0, burst_fired = false,
  last_tap = -100, pending_page_at = nil,
  send_page = 1, page_count = 1, page_names = {}, flash_until = 0, flash_page = 1,
  tsend = {}, rec_held = nil, rec_tr = nil, rec_used = false, anim = nil,
  led = {}, led_t = -100,
  sp_owned = {}, sp_dirty = true, sp_checked = false,
  mode = "mixer", binds = {}, bind_res = {}, learn_key = nil, learn_mode = false, mode_flash = nil, binds_proj = nil,
  meters = {}, markers = {}, tinted = {}, sig_t = -100,
  rec_mode = 1, mode_flash_until = 0, solo_tap_t = -100,
  slots = {}, types = {}, manual = {}, tcache = {},
  last_rebuild = -100, err_count = 0, gui_open = true,
}

function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
function log10(x) return math.log(x, 10) end
