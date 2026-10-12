-- MidiMix module: MIDI input: buttons, knobs, faders, LEDs. Loaded by midimix_reaper.lua into a shared environment.
-- Top-level names here are shared between modules (the 'local' keyword is dropped on purpose).


function sendall_short()
  if not S.enabled then return end
  if S.rec_held then
    next_track_send(S.rec_held)
    S.rec_used = true
  elseif S.solo_held then
    if S.mode == "instrument" then R.CSurf_GoStart() else clear_all_solo() end
    S.solo_used = true
  elseif CFG.global_sends and S.mode == "mixer" then
    next_page()
  else
    toggle_mode(R.time_precise())
  end
end

function on_note(note, down, now)
  local b = note_of[note]
  if not b then
    dbg("unknown note", note, down and "pressed" or "released")
    return
  end
  if b.kind == "sendall" then
    if down then
      S.sa_down, S.sa_t, S.sa_trig = true, now, false
    else
      if S.sa_down and not S.sa_trig then sendall_short() end
      S.sa_down = false
    end
    return
  end
  if not S.enabled then return end

  if S.mode == "instrument" and (b.kind == "mute" or b.kind == "rec" or b.kind == "solostrip") then
    if down then
      if b.kind == "mute" then inst_mute(b.strip) elseif b.kind == "rec" then inst_rec(b.strip) end
      if S.solo_held then S.solo_used = true end
    end
    return
  end

  if b.kind == "mute" then
    if down then
      local tr = S.strips[b.strip]
      if tr then
        if S.solo_held then
          set_solo(tr, info(tr, "I_SOLO") == 0)
          S.solo_used = true
        else
          set_mute(tr, info(tr, "B_MUTE") == 0)
        end
      end
    end
  elseif b.kind == "solostrip" then
    if down then
      local tr = S.strips[b.strip]
      if tr then set_solo(tr, info(tr, "I_SOLO") == 0) end
      S.solo_used = true
    end
  elseif b.kind == "rec" then
    if down then
      if S.solo_held then
        bank_rec_toggle()
        S.solo_used = true
      elseif CFG.track_sends and S.strips[b.strip] then
        -- the arm toggle happens on release, unless Send All was used while held
        S.rec_held, S.rec_used = b.strip, false
      else
        local tr = S.strips[b.strip]
        if tr then rec_toggle(tr) end
      end
    elseif S.rec_held == b.strip then
      if not S.rec_used then
        local tr = S.strips[b.strip]
        if tr then rec_toggle(tr) end
      end
      S.rec_held = nil
    end
  elseif b.kind == "solo" then
    if down then
      S.solo_held, S.solo_used = true, false
    else
      S.solo_held = false
      if not S.solo_used then
        bank_solo_toggle()
        if CFG.rec_modes and now - S.solo_tap_t <= CFG.double_tap_s then
          -- second tap: the first tap's bank solo is undone by this one, and the Rec row changes mode
          S.solo_tap_t = -100
          set_rec_mode(S.rec_mode % #REC_MODES + 1, now)
        else
          S.solo_tap_t = now
        end
      end
    end
  elseif b.kind == "bank" then
    local d = b.dir
    if down then
      S.bank_down[d], S.bank_used[d] = true, false
      S.bank_t[d] = now
      if S.solo_held then
        bank_nudge(d)
        S.solo_used, S.bank_used[d] = true, true
      elseif S.bank_down[-d] then
        if S.mode == "instrument" then R.Main_OnCommand(40044, 0) else bank_stereo_pan() end   -- 40044 = play/stop
        S.bank_used[d], S.bank_used[-d] = true, true
      end
    else
      S.bank_down[d] = false
      if not S.bank_used[d] then bank_page(d) end
    end
  end
end

---------------------------------------------------------------------------
-- KNOBS AND FADERS (with pickup)
---------------------------------------------------------------------------
function on_sendall_burst(now)
  -- fallback if Send All does not send its own note
  if S.rec_held and S.enabled then
    next_track_send(S.rec_held)
    S.rec_used = true
    return
  end
  if S.solo_held and S.enabled then
    if S.mode == "instrument" then R.CSurf_GoStart() else clear_all_solo() end
    S.solo_used = true
    return
  end
  if now - S.last_tap <= CFG.double_tap_s then
    S.pending_page_at = nil
    S.last_tap = -100
    toggle_enabled("double Send All (CC dump)")
  else
    S.last_tap = now
    S.pending_page_at = now + CFG.double_tap_s
  end
end

function track_burst(cc, now)
  if CFG.send_all_note then return end
  if now - S.burst_t0 > CFG.burst_window then
    S.burst_t0, S.burst_seen, S.burst_cnt, S.burst_fired = now, {}, 0, false
  end
  if not S.burst_seen[cc] then
    S.burst_seen[cc] = true
    S.burst_cnt = S.burst_cnt + 1
    if S.burst_cnt >= CFG.burst_min and not S.burst_fired then
      S.burst_fired = true
      on_sendall_burst(now)
    end
  end
end

function on_cc(cc, val, now)
  local c = cc_of[cc]
  if not c then
    dbg("unknown CC", cc, val)
    return
  end
  track_burst(cc, now)
  local prev = S.phys[cc]
  S.phys[cc] = val
  if not S.enabled then return end
  if c.strip and c.strip > CFG.bank_size then return end

  if S.mode == "instrument" and (c.kind == "top" or c.kind == "mid" or c.kind == "bot") then
    local bk = c.kind .. c.strip
    if S.solo_held then                       -- Solo + knob: forget this binding
      clear_bind(bk)
      S.solo_used = true
      return
    end
    if S.learn_mode and prev ~= nil and math.abs(val - prev) > 0 then
      if S.learn_key ~= bk then start_learn(bk) end
    end
    local b = resolve_bind(bk, now)
    if not b then return end
    c = { kind = "fxbind", strip = c.strip, bk = bk, b = b }
  end

  local tr = track_for(c)
  if not tr then return end
  local key = key_of(c)

  if c.kind == "mid" and S.solo_held then
    -- Solo + middle knob: switch the track to stereo pan
    set_info(tr, "I_PANMODE", 5)
    S.solo_used = true
    S.picked[key] = nil
    return
  end

  local ad = A[c.kind]
  local cur = ad.get(tr, c)
  if cur == nil then return end
  local v = val / 127

  if not S.picked[key] then
    local crossed = prev ~= nil and ((prev / 127 - cur) * (v - cur) <= 0)
    if math.abs(v - cur) <= CFG.pickup_window / 127 or crossed then
      S.picked[key] = true
      S.key_info[key] = c
    else
      return
    end
  end
  ad.set(tr, v, c)
  S.last[key] = ad.get(tr, c)
end

-- If a parameter was changed in REAPER itself, pickup is needed again.
function check_external()
  for key, picked in pairs(S.picked) do
    if picked then
      local c = S.key_info[key]
      if c and c.kind == "fxbind" then
        c.b = resolve_bind(c.bk)              -- the plugin may be gone
        if not c.b then c = nil end
      end
      local tr = c and track_for(c)
      local cur = tr and A[c.kind].get(tr, c)
      if cur == nil or math.abs(cur - (S.last[key] or cur)) > 0.01 then
        S.picked[key] = nil
      end
    end
  end
end

---------------------------------------------------------------------------
-- READING MIDI
---------------------------------------------------------------------------
function poll_midi(now)
  local newest
  local evs = {}
  for idx = 0, 4095 do
    local seq, buf, _, dev = R.MIDI_GetRecentInputEvent(idx)
    if not seq or seq == 0 then break end
    if idx == 0 then newest = seq end
    if S.last_seq and seq <= S.last_seq then break end
    if S.last_seq and S.in_idx[dev] and buf and #buf >= 3 then evs[#evs + 1] = buf end
  end
  if newest then S.last_seq = newest elseif S.last_seq == nil then S.last_seq = 0 end

  for k = #evs, 1, -1 do
    local b1, b2, b3 = evs[k]:byte(1, 3)
    local t, ch = b1 & 0xF0, b1 & 0x0F
    if CFG.midi_channel == nil or ch == CFG.midi_channel then
      if t == 0xB0 then on_cc(b2, b3, now)
      elseif t == 0x90 then on_note(b2, b3 > 0, now)
      elseif t == 0x80 then on_note(b2, false, now) end
    end
  end
end

---------------------------------------------------------------------------
-- LEDs
---------------------------------------------------------------------------
function update_leds(now)
  local m = CFG.map
  local force = now - S.led_t >= CFG.led_refresh_s
  if force then S.led_t = now end
  local want = {}
  if S.anim then
    -- start-up circle: Mute 1..8, then Rec 8..1, one LED at a time
    if not S.anim.t0 then S.anim.t0 = now end
    local idx = math.floor((now - S.anim.t0) / CFG.startup_step_s) + 1
    if idx > #S.anim.seq then
      S.anim = nil
      S.led = {}  -- the normal state is sent again right below
      force = true
    else
      want[S.anim.seq[idx]] = true
    end
  end
  if not S.anim then
    if S.enabled then
      local blink = math.floor(now * CFG.blink_hz * 2) % 2 == 0
      local flashing = now < S.flash_until
      for i = 1, CFG.bank_size do
        local tr = S.strips[i]
        local mu, re = false, false
        if S.mode == "instrument" then
          local b = strip_main_bind(i)
          if b then
            mu = R.TrackFX_GetFloatingWindow(b.tr, b.fx) ~= nil
            re = info(b.tr, "I_SELECTED") ~= 0
          end
          if S.learn_key and tonumber(S.learn_key:match("%d+$")) == i then mu = blink end
        elseif tr then
          local soloed = info(tr, "I_SOLO") ~= 0
          if CFG.solo_leds_on_mute and S.solo_held then mu = soloed
          elseif soloed then mu = blink
          else mu = info(tr, "B_MUTE") ~= 0 end
          if m.solo_strip then want[m.solo_strip[i]] = soloed end
          if flashing then
            if S.flash_page <= 8 then re = i <= S.flash_page
            else re = blink and i <= math.min(S.flash_page - 8, 8) end
          elseif now < S.mode_flash_until then re = i <= S.rec_mode
          else re = rec_state(tr) end
        end
        want[m.mute[i]] = mu
        want[m.rec[i]] = re
      end
      if S.mode_flash then
        if now < S.mode_flash.t_end then
          for i = 1, 8 do want[S.mode_flash.row == "mute" and m.mute[i] or m.rec[i]] = true end
        else
          S.mode_flash = nil
        end
      end
      -- Bank Right blinks faster the further the bank is from the first one;
      -- on the first bank both Bank LEDs are dark
      local b = math.ceil((S.first - 1) / CFG.bank_size)
      if b > 0 then
        local hz = math.min(CFG.bank_blink_base_hz + (b - 1) * CFG.bank_blink_step_hz, CFG.bank_blink_max_hz)
        want[m.bank_right] = math.floor(now * hz * 2) % 2 == 0
      end
    else
      -- paused: both Bank LEDs lit steadily, everything else dark
      want[m.bank_left], want[m.bank_right] = true, true
    end
  end
  for _, note in ipairs(led_notes) do led_set(note, want[note] or false, force) end
end

