-- MidiMix module: Control map, MIDI output, LEDs, track setters, Rec modes, sends. Loaded by midimix_reaper.lua into a shared environment.
-- Top-level names here are shared between modules (the 'local' keyword is dropped on purpose).

---------------------------------------------------------------------------
-- CONTROL MAP
---------------------------------------------------------------------------
cc_of, note_of = {}, {}
led_notes = {}
do
  local m = CFG.map
  for i = 1, 8 do
    cc_of[m.fader[i]]    = { kind = "fader", strip = i }
    cc_of[m.knob_top[i]] = { kind = "top", strip = i }
    cc_of[m.knob_mid[i]] = { kind = "mid", strip = i }
    cc_of[m.knob_bot[i]] = { kind = "bot", strip = i }
    note_of[m.mute[i]]   = { kind = "mute", strip = i }
    note_of[m.rec[i]]    = { kind = "rec", strip = i }
    led_notes[#led_notes + 1] = m.mute[i]
    led_notes[#led_notes + 1] = m.rec[i]
  end
  if m.solo_strip then
    for i = 1, 8 do
      local n = m.solo_strip[i]
      if n and not note_of[n] then
        note_of[n] = { kind = "solostrip", strip = i }
        led_notes[#led_notes + 1] = n  -- the device shows these LEDs on the Mute row while Solo is held
      end
    end
  end
  cc_of[m.master] = { kind = "master" }
  note_of[m.bank_left]  = { kind = "bank", dir = -1 }
  note_of[m.bank_right] = { kind = "bank", dir = 1 }
  note_of[m.solo]       = { kind = "solo" }
  led_notes[#led_notes + 1] = m.bank_left
  led_notes[#led_notes + 1] = m.bank_right
  if CFG.send_all_note then note_of[CFG.send_all_note] = { kind = "sendall" } end
end

---------------------------------------------------------------------------
-- DEVICE AND MIDI
---------------------------------------------------------------------------
function scan_devices(now)
  S.last_scan = now
  local old_out = S.out_idx
  S.in_idx, S.out_idx = {}, nil
  local n_in = R.GetNumMIDIInputs()
  for i = 0, n_in - 1 do
    local ok, name = R.GetMIDIInputName(i, "")
    if ok and name and name:lower():find(CFG.device_match) then S.in_idx[i] = true end
  end
  local n_out = R.GetNumMIDIOutputs()
  for i = 0, n_out - 1 do
    local ok, name = R.GetMIDIOutputName(i, "")
    if ok and name and name:lower():find(CFG.device_match) then S.out_idx = i; break end
  end
  local had = S.device_ok
  S.device_ok = next(S.in_idx) ~= nil
  if S.device_ok and not had then dbg("MidiMix found") end
  if not S.device_ok and had then dbg("MidiMix lost") end
  if S.device_ok ~= had or S.out_idx ~= old_out then
    S.led = {} -- resend the LEDs after (re)connecting
    if CFG.startup_anim and S.out_idx ~= nil and S.device_ok then
      local m, seq = CFG.map, {}
      for i = 1, 8 do seq[#seq + 1] = m.mute[i] end
      for i = 8, 1, -1 do seq[#seq + 1] = m.rec[i] end
      S.anim = { seq = seq, t0 = nil }
    end
  end
end

function send_midi(b1, b2, b3)
  if S.out_idx ~= nil then R.StuffMIDIMessage(16 + S.out_idx, b1, b2, b3) end
end

function led_set(note, on, force)
  local v = on and 127 or 0
  if force or S.led[note] ~= v then
    S.led[note] = v
    send_midi(0x90 | (CFG.midi_channel or 0), note, v)
  end
end

---------------------------------------------------------------------------
-- VOLUME: REAPER fader curve
---------------------------------------------------------------------------
function max_slider() return R.DB2SLIDER(CFG.fader_max_db) end
function gain_from_norm(n)
  if n <= 0 then return 0 end
  local db = R.SLIDER2DB(n * max_slider())
  return 10 ^ (db / 20)
end
function norm_from_gain(g)
  if g <= 0.0000001 then return 0 end
  return clamp(R.DB2SLIDER(20 * log10(g)) / max_slider(), 0, 1)
end

---------------------------------------------------------------------------
-- REAPER WRAPPERS
---------------------------------------------------------------------------
function info(tr, name) return R.GetMediaTrackInfo_Value(tr, name) end
function set_info(tr, name, v) R.SetMediaTrackInfo_Value(tr, name, v) end
function guid(tr) return R.GetTrackGUID(tr) end

function set_vol(tr, gain)
  if not pcall(R.CSurf_OnVolumeChange, tr, gain, false) then set_info(tr, "D_VOL", gain) end
end
function set_pan(tr, pan)
  if not pcall(R.CSurf_OnPanChange, tr, pan, false) then set_info(tr, "D_PAN", pan) end
end
function set_width(tr, w)
  if not pcall(R.CSurf_OnWidthChange, tr, w, false) then set_info(tr, "D_WIDTH", w) end
end
function set_mute(tr, mute)
  if not pcall(R.CSurf_OnMuteChange, tr, mute and 1 or 0) then set_info(tr, "B_MUTE", mute and 1 or 0) end
end
function set_recarm(tr, arm)
  if not pcall(R.CSurf_OnRecArmChange, tr, arm and 1 or 0) then set_info(tr, "I_RECARM", arm and 1 or 0) end
end

-- What the Rec row does. 1 = rec arm, 2 = mute of the track's current send, 3 = bypass of the whole FX chain.
-- "on" (LED lit, flag lit) means: armed / send muted / FX bypassed.
REC_MODES = {
  { name = "arm",  letter = "R", label = "Rec arm" },
  { name = "send", letter = "T", label = "Send mute" },
  { name = "fx",   letter = "F", label = "FX bypass" },
}
function rec_state(tr)
  local m = S.rec_mode
  if m == 1 then return info(tr, "I_RECARM") ~= 0 end
  if m == 2 then
    local k = rec_send_index and rec_send_index(tr)
    return k ~= nil and R.GetTrackSendInfo_Value(tr, 0, k, "B_MUTE") ~= 0
  end
  return info(tr, "I_FXEN") == 0
end
function rec_set(tr, on)
  local m = S.rec_mode
  if m == 1 then set_recarm(tr, on)
  elseif m == 2 then
    local k = rec_send_index and rec_send_index(tr)
    if k ~= nil then R.SetTrackSendInfo_Value(tr, 0, k, "B_MUTE", on and 1 or 0) end
  else
    set_info(tr, "I_FXEN", on and 0 or 1)
  end
end
function rec_toggle(tr) rec_set(tr, not rec_state(tr)) end
function set_rec_mode(m, now)
  S.rec_mode = m
  S.mode_flash_until = now + CFG.page_flash_s
  dbg("rec mode ->", REC_MODES[m].name)
end
function set_solo(tr, on) set_info(tr, "I_SOLO", on and CFG.solo_value or 0) end

function dest_name(tr, k)
  local dest = R.GetTrackSendInfo_Value(tr, 0, k, "P_DESTTRACK")
  if not dest or dest == 0 then return nil end
  local _, name = R.GetTrackName(dest, "")
  return name
end

-- Which send of the track is on the current page? Returns the send index (from 0) or nil.
function send_index(tr)
  local n = R.GetTrackNumSends(tr, 0)
  local ov = S.tsend[guid(tr)]  -- per-track choice (Rec N held + Send All)
  if ov ~= nil and ov < n then return ov end
  if CFG.sends_by_name then
    local name = S.page_names[S.send_page]
    if not name then return nil end
    for k = 0, n - 1 do
      if dest_name(tr, k) == name then return k end
    end
    return nil
  end
  if S.send_page <= n then return S.send_page - 1 end
  return nil
end

