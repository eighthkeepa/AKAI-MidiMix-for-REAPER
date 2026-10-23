-- @noindex
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (c) 2026 The Eighth
-- MidiMix module: Window (ReaImGui). Loaded by AKAI MidiMix.lua into a shared environment.
-- Top-level names here are shared between modules (the 'local' keyword is dropped on purpose).

---------------------------------------------------------------------------
-- WINDOW (ReaImGui, optional)
---------------------------------------------------------------------------
HAVE_GUI = CFG.window and R.ImGui_CreateContext ~= nil

function rgba(col)
  if not col or col == 0 then return 0xCCCCCCFF end
  local r, g, b = R.ColorFromNative(col)
  return (r << 24) | (g << 16) | (b << 8) | 0xFF
end

function strips_valid()
  if not R.ValidatePtr2 then return true end
  for i = 1, CFG.bank_size do
    local tr = S.slots[i]
    if tr and not R.ValidatePtr2(0, tr, "MediaTrack*") then return false end
  end
  return true
end

function report_error(where, err)
  local msg = where .. ": " .. tostring(err)
  if msg ~= S.last_err then
    S.last_err = msg
    say("error", msg)
    dbg("error", msg)
  end
end

-- Palette (0xRRGGBBAA)
C = {
  panel = 0x24262BFF, strip = 0x30323AFF, header = 0x23252AFF, sep = 0x08090BFF, bar_bg = 0x15161AFF,
  text = 0xE8E9ECFF, dim = 0x8C919BFF,
  akai = 0xBC012EFF, akai_dim = 0x7A0120FF,   -- Akai Red (#BC012E) for the window title bar
  vol = 0x3FB6A8FF, pan = 0x6C8EF5FF, wid = 0xB07CF0FF, send = 0xF0A13DFF,
  m_on = 0xE8A33DFF, s_on = 0x4CBF6BFF, r_on = 0xE5484DFF, flag_off = 0x30333AFF,
  ok = 0x4CBF6BFF, paused = 0xE8A33DFF, bad = 0xE5484DFF,
  zero = 0xFFFFFF8C, head = 0xFF5470FF, mpc_meter = 0x2EC4D6FF, mpc_cap = 0xD8DAE0FF,
}
G = { W = 104, WM = 80, GAP = 3, PAD = 6, H = 374 }
function SW() return CFG.mixer_style == "mpc" and G.WM or G.W end   -- strip width of the chosen look

function text_on(col)  -- black or white text, whichever reads better on this colour
  local r, g, b = (col >> 24) & 255, (col >> 16) & 255, (col >> 8) & 255
  return (r * 299 + g * 587 + b * 114) / 1000 > 140 and 0x111111FF or 0xFFFFFFFF
end

-- Cut a UTF-8 string so that it fits into max_w pixels
function fit(text, max_w)
  if R.ImGui_CalcTextSize(ctx, text) <= max_w then return text end
  local n = utf8.len(text) or #text
  while n > 1 do
    n = n - 1
    local cut = text:sub(1, (utf8.offset(text, n + 1) or (#text + 1)) - 1)
    if R.ImGui_CalcTextSize(ctx, cut .. "..") <= max_w then return cut .. ".." end
  end
  return ".."
end

-- invisible area that shows a short hint when the mouse rests on it
function tip_zone(id, x, y, w, h, text)
  if not CFG.tooltips or not R.ImGui_SetItemTooltip then return end
  R.ImGui_SetCursorScreenPos(ctx, x, y)
  R.ImGui_InvisibleButton(ctx, id, w, h)
  R.ImGui_SetItemTooltip(ctx, L(text))
end

function db_text(gain)
  if gain <= 0.0000316 then return "-inf" end
  return string.format("%.1f", 20 * log10(gain))
end

TYPE_INFO = {
  audio      = { "Audio",      0x3FB6A8FF },
  instrument = { "Instrument", 0xB07CF0FF },
  bus        = { "Bus",        0xF0A13DFF },
  vca        = { "VCA",        0xE5484DFF },
  folder     = { "Folder",     0xE8D44DFF },
  separator  = { "Separator",  0x8C919BFF },
}

-- small icon (about 16x12) for a track type, drawn with draw-list shapes
function type_icon(dl, ty, x, y, col)
  local L = function(x1, y1, x2, y2, t) R.ImGui_DrawList_AddLine(dl, x + x1, y + y1, x + x2, y + y2, col, t or 1.5) end
  local B = function(x1, y1, x2, y2) R.ImGui_DrawList_AddRectFilled(dl, x + x1, y + y1, x + x2, y + y2, col, 1) end
  if ty == "audio" then            -- waveform
    local h = { 3, 8, 12, 6, 10, 4, 7 }
    for k, v in ipairs(h) do B((k - 1) * 2.4, (12 - v) / 2, (k - 1) * 2.4 + 1.5, (12 + v) / 2) end
  elseif ty == "instrument" then   -- piano keys
    R.ImGui_DrawList_AddRect(dl, x, y, x + 16, y + 12, col, 1)
    L(5.3, 0, 5.3, 12, 1); L(10.6, 0, 10.6, 12, 1)
    B(3.6, 0, 7, 7); B(8.9, 0, 12.3, 7)
  elseif ty == "bus" then          -- inputs merging into one line
    L(0, 1, 7, 6); L(0, 6, 7, 6); L(0, 11, 7, 6); L(7, 6, 16, 6, 2)
    R.ImGui_DrawList_AddCircleFilled(dl, x + 7, y + 6, 2, col)
  elseif ty == "vca" then          -- fader
    L(8, 0, 8, 12, 1.5); B(3, 3, 13, 7)
  elseif ty == "folder" then       -- folder
    B(0, 2, 6, 4); B(0, 4, 16, 12)
  elseif ty == "separator" then    -- dashed line
    B(0, 5, 4, 7); B(6, 5, 10, 7); B(12, 5, 16, 7)
  end
end

function cycle_type(i)
  local tr = S.slots[i]
  if not tr then return end
  local cur = S.manual[i] and S.types[i] or nil
  local nxt
  if not cur then nxt = TYPE_ORDER[1]
  else
    for k, t in ipairs(TYPE_ORDER) do if t == cur then nxt = TYPE_ORDER[k + 1] end end
  end
  write_override(tr, nxt)        -- nil after the last type = back to automatic
  S.tcache[guid(tr)] = nil
  S.last_rebuild = -100
end

-- writes everything we could use to tell track types apart (to midimix_tracks.txt)
function dump_tracks()
  local f = io.open(R.GetResourcePath() .. "/midimix_tracks.txt", "w")
  if not f then return end
  local keys = { "I_FOLDERDEPTH", "I_FOLDERCOMPACT", "I_SPACER", "I_TCPH", "I_HEIGHTOVERRIDE", "B_SHOWINTCP",
                 "B_SHOWINMIXER", "B_MAINSEND", "I_NCHAN", "I_PANMODE", "I_PLAY_OFFSET_FLAG" }
  for i = 0, math.min(R.CountTracks(0), 80) - 1 do
    local tr = R.GetTrack(0, i)
    local _, name = R.GetTrackName(tr, "")
    local parts = { string.format("#%d %q", i + 1, tostring(name)) }
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(safe(R.GetMediaTrackInfo_Value, tr, k)) end
    parts[#parts + 1] = "items=" .. tostring(safe(R.CountTrackMediaItems, tr))
    parts[#parts + 1] = "fx=" .. tostring(safe(R.TrackFX_GetCount, tr))
    parts[#parts + 1] = "sends=" .. tostring(safe(R.GetTrackNumSends, tr, 0))
    parts[#parts + 1] = "recvs=" .. tostring(safe(R.GetTrackNumSends, tr, -1))
    parts[#parts + 1] = "hwouts=" .. tostring(safe(R.GetTrackNumSends, tr, 1))
    for _, g in ipairs({ "VOLUME_VCA_MASTER", "VOLUME_VCA_SLAVE", "VOLUME_LEAD", "VOLUME_FOLLOW" }) do
      local lo, hi = vca_flags(tr, g)
      parts[#parts + 1] = g .. "=" .. tostring(lo) .. "/" .. tostring(hi)
    end
    parts[#parts + 1] = "override=" .. tostring(read_override(tr))
    parts[#parts + 1] = "auto=" .. tostring((compute_type(tr)))
    for _, k in ipairs({ "P_ICON", "P_NAME", "P_TCP_LAYOUT", "P_MCP_LAYOUT" }) do
      local ok, a, b = pcall(R.GetSetMediaTrackInfo_String, tr, k, "", false)
      parts[#parts + 1] = k .. "=" .. tostring(ok and (type(a) == "string" and a or b) or "?")
    end
    f:write(table.concat(parts, "  "), "\n")
  end
  f:close()
  say("track info written to " .. R.GetResourcePath() .. "/midimix_tracks.txt")
end

-- level meters: smoothed peaks with a hold line
function meter_values(tr, now, master)
  local g = guid(tr)
  local m = S.meters[g]
  if not m then m = { l = 0, r = 0, hl = 0, hr = 0, th = now }; S.meters[g] = m end
  local dt = math.min(0.2, now - (m.t or now))
  m.t = now
  local pl = (R.Track_GetPeakInfo and R.Track_GetPeakInfo(tr, 0)) or 0
  local pr = (R.Track_GetPeakInfo and R.Track_GetPeakInfo(tr, 1)) or pl
  if CFG.meter_after_fader then
    local gain = info(tr, "B_MUTE") ~= 0 and 0 or info(tr, "D_VOL")
    pl, pr = pl * gain, pr * gain
  end
  if CFG.meter_after_pan and not master then   -- pan as balance: the far side gets quieter
    local pan = info(tr, "D_PAN")
    if pan > 0 then pl = pl * (1 - pan) elseif pan < 0 then pr = pr * (1 + pan) end
  end
  local fall = dt * 2.5                       -- how fast the bar falls (linear units per second)
  m.l = pl >= m.l and pl or math.max(pl, m.l - fall * m.l - 0.0005)
  m.r = pr >= m.r and pr or math.max(pr, m.r - fall * m.r - 0.0005)
  if m.l > m.hl or now - m.th > 2 then m.hl = m.l; m.th = now end
  if m.r > m.hr then m.hr = m.r; m.th = now end
  if now - m.th > 2 then m.hl, m.hr = m.l, m.r end
  return m
end

function lighten(col, amt)    -- col = 0xRRGGBBAA; mix with white so dark colours stay readable on a dark panel
  local r, g, b = (col >> 24) & 255, (col >> 16) & 255, (col >> 8) & 255
  local lum = (r * 299 + g * 587 + b * 114) / 1000
  if lum >= 110 then return col end
  r, g, b = r + (255 - r) * amt, g + (255 - g) * amt, b + (255 - b) * amt
  return (math.floor(r) << 24) | (math.floor(g) << 16) | (math.floor(b) << 8) | 0xFF
end

-- scale marks follow the fader top from the settings (e.g. +12 dB)
function fader_ticks()
  local top = CFG.fader_max_db or 12
  local t = {}
  for _, d in ipairs({ 12, 9, 6, 3, 0, -3, -9, -20, -30 }) do
    if d <= top + 0.001 then t[#t + 1] = d end
  end
  if #t == 0 or top - t[1] > 1.2 then table.insert(t, 1, top) end
  local out = {}
  for _, d in ipairs(t) do
    out[#out + 1] = { d, d > 0.001 and string.format("+%g", d) or string.format("%g", d) }
  end
  return out
end

-- fader scale + stereo meters + fader handle + dB numbers; shared by track strips and the master strip
function draw_fader_area(dl, ix, inner, y, tr, mcol, master, now)
  local function rect(x1, y1, x2, y2, col, rnd) R.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, col, rnd or 0) end
  local function label(tx, ty, col, str) R.ImGui_DrawList_AddText(dl, tx, ty, col, str) end
  local ay, ah = y + 124, 176
  local sx1 = ix + 24
  local function ypos(norm) return ay + ah - 2 - clamp(norm, 0, 1) * (ah - 4) end
  local last_y
  local zy = ypos(norm_from_gain(1))             -- the 0 dB line is always drawn and stands out
  for _, t in ipairs(fader_ticks()) do
    local yy = ypos(norm_from_gain(10 ^ (t[1] / 20)))
    if t[1] ~= 0 and math.abs(yy - zy) >= 13 and (not last_y or math.abs(yy - last_y) >= 13) then
      R.ImGui_DrawList_AddLine(dl, sx1, yy, ix + inner, yy, 0xFFFFFF30, 1)
      label(ix, yy - 6, C.dim, t[2])
      last_y = yy
    end
  end
  if (CFG.fader_max_db or 12) >= 0 then
    R.ImGui_DrawList_AddLine(dl, sx1 - 3, zy, ix + inner, zy, C.zero, 1)
    label(ix, zy - 6, C.text, "0")
  end
  label(ix, ay + ah - 14, C.dim, "inf")
  local mw, mgap = 15, 2
  local mx = sx1 + 4
  local m = meter_values(tr, now, master)
  for side = 0, 1 do
    local v = side == 0 and m.l or m.r
    local hv = side == 0 and m.hl or m.hr
    local x1 = mx + side * (mw + mgap)
    local top = ypos(norm_from_gain(math.max(v, 1e-5)))
    if v > 0.00002 then rect(x1, top, x1 + mw, ay + ah - 2, mcol, 0) end
    local ht = ypos(norm_from_gain(math.max(hv, 1e-5)))
    if hv > 0.00002 then rect(x1, ht - 1, x1 + mw, ht + 1, lighten(mcol, 0.6) | 0xFF, 0) end
  end
  local vol = info(tr, "D_VOL")
  local fy = ypos(norm_from_gain(vol))
  R.ImGui_DrawList_AddLine(dl, sx1, fy, ix + inner - 6, fy, 0xFFFFFFFF, 2)
  R.ImGui_DrawList_AddRectFilled(dl, ix + inner - 9, fy - 6, ix + inner, fy + 6, 0xFFFFFFFF, 3)
  local peak = math.max(m.hl, m.hr)
  label(ix, y + 304, C.text, db_text(vol) .. "dB")
  local ptxt2 = (peak > 0.00002) and (db_text(peak) .. "dB") or "-inf dB"
  local pw = R.ImGui_CalcTextSize(ctx, ptxt2)
  label(ix + inner - pw, y + 304, peak > 1 and C.bad or C.dim, ptxt2)
end

-- one channel strip, in the style of the Akai MPC mixer
function draw_strip(dl, x, y, i, tr)
  local W, H = G.W, G.H
  local PADX = 7
  local inner = W - 2 * PADX
  local ix = x + PADX
  local now = R.time_precise()
  local function rect(x1, y1, x2, y2, col, rnd) R.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, col, rnd or 0) end
  local function label(tx, ty, col, str) R.ImGui_DrawList_AddText(dl, tx, ty, col, str) end
  local function centered(cx, ty, col, str)
    local tw = R.ImGui_CalcTextSize(ctx, str)
    label(cx - tw / 2, ty, col, str)
  end
  -- a horizontal bar with text; centre = true: fills from the middle
  local function bar(by, h, norm, col, str, centre)
    rect(ix, by, ix + inner, by + h, C.bar_bg, 2)
    norm = clamp(norm, 0, 1)
    if centre then
      local mid = ix + inner / 2
      local px = ix + inner * norm
      if px >= mid then rect(mid, by, math.max(px, mid + 1), by + h, col, 2)
      else rect(px, by, mid, by + h, col, 2) end
      R.ImGui_DrawList_AddLine(dl, mid, by, mid, by + h, 0xFFFFFF55, 1)
    elseif norm > 0 then
      rect(ix, by, ix + inner * norm, by + h, col, 2)
    end
    centered(ix + inner / 2, by + (h - 13) / 2, C.text, str)
  end

  rect(x, y, x + W, y + H, C.strip, 0)
  if not tr then
    label(ix, y + 8, C.dim, tostring(S.first + i - 1 > S.nvis and "-" or i) .. "  " .. L("(empty)"))
    R.ImGui_DrawList_AddRect(dl, x, y, x + W, y + H, C.sep, 0, 0, 2)
    return
  end

  local ty = S.types[i] or "audio"
  local tinfo = TYPE_INFO[ty] or TYPE_INFO.audio
  local _, name = R.GetTrackName(tr, "")
  local ncol = rgba(R.GetTrackColor(tr))
  local has_col = (R.GetTrackColor(tr) or 0) ~= 0
  local selected = info(tr, "I_SELECTED") ~= 0
  local num = tostring(S.first + i - 1)

  -- coloured line + header (filled with the track colour while the track is selected in REAPER)
  rect(x, y, x + W, y + 3, has_col and ncol or tinfo[2], 0)
  local hcol = selected and ncol or C.header
  rect(x, y + 3, x + W, y + 47, hcol, 0)
  local fg = selected and text_on(ncol) or (has_col and lighten(ncol, 0.45) or C.text)
  type_icon(dl, ty, ix, y + 9, selected and text_on(ncol) or tinfo[2])
  label(ix + 22, y + 7, fg, num)
  label(ix, y + 26, fg, fit(name or "?", inner))
  R.ImGui_SetCursorScreenPos(ctx, x, y + 3)
  if R.ImGui_InvisibleButton(ctx, "type" .. i, W, 22) then cycle_type(i) end
  if R.ImGui_SetItemTooltip then
    R.ImGui_SetItemTooltip(ctx, L(tinfo[1]) .. L(S.manual[i] and " (set by hand)" or " (automatic)") .. L(". Click to change."))
  end

  if ty == "separator" then   -- never controlled
    local nc = L("not controlled")
    local mw = R.ImGui_CalcTextSize(ctx, nc)
    label(x + (W - mw) / 2, y + H / 2 - 6, C.dim, nc)
    R.ImGui_DrawList_AddRect(dl, x, y, x + W, y + H, C.sep, 0, 0, 2)
    return
  end

  local pan = info(tr, "D_PAN")
  local ptxt = math.abs(pan) < 0.005 and "C" or string.format("%s%d", pan < 0 and "L" or "R", math.floor(math.abs(pan) * 100 + 0.5))
  bar(y + 53, 14, (pan + 1) / 2, C.pan, ptxt, true)
  if width_active(tr) then
    local width = info(tr, "D_WIDTH")
    bar(y + 70, 12, (width + 1) / 2, C.wid, string.format("width %d", math.floor(width * 100 + 0.5)), true)
  else
    bar(y + 70, 12, 0.5, C.flag_off, L("width n/a"))
  end

  -- send
  local nsend = R.GetTrackNumSends(tr, 0)
  local k = send_index(tr)
  if nsend == 0 then
    label(ix, y + 88, C.dim, L("no sends"))
    bar(y + 104, 12, 0, C.send, "-")
  else
    local count = string.format("%d/%d", k and (k + 1) or 0, nsend)
    local cw = R.ImGui_CalcTextSize(ctx, count)
    label(ix + inner - cw, y + 88, k and C.send or C.dim, count)
    local dest = k and dest_name(tr, k)
    label(ix, y + 88, k and C.text or C.dim, fit(dest or (k and L("send") or "-"), inner - cw - 4))
    if k then
      local sv = R.GetTrackSendInfo_Value(tr, 0, k, "D_VOL")
      bar(y + 104, 12, norm_from_gain(sv), C.send, db_text(sv) .. " dB")
    else
      bar(y + 104, 12, 0, C.send, "-")
    end
  end

  draw_fader_area(dl, ix, inner, y, tr, has_col and ncol or tinfo[2], false, now)

  -- M S R / T / F buttons
  local fw = (inner - 8) / 3
  local flags = {
    { "M", info(tr, "B_MUTE") ~= 0, C.m_on },
    { "S", info(tr, "I_SOLO") ~= 0, C.s_on },
    { REC_MODES[S.rec_mode].letter, rec_state(tr), C.r_on },
  }
  for f = 1, 3 do
    local fx = ix + (f - 1) * (fw + 4)
    local on = flags[f][2]
    rect(fx, y + 326, fx + fw, y + 348, on and flags[f][3] or C.flag_off, 3)
    centered(fx + fw / 2, y + 330, on and text_on(flags[f][3]) or C.dim, flags[f][1])
  end

  tip_zone("tp_pan" .. i, ix, y + 53, inner, 14, "Pan (bottom knob).")
  tip_zone("tp_wid" .. i, ix, y + 70, inner, 12, "Width (middle knob). Only works on tracks in stereo pan mode.")
  tip_zone("tp_snd" .. i, ix, y + 86, inner, 30, "Send level (top knob). Hold Rec and tap Send All for this track's next send.")
  tip_zone("tp_vol" .. i, ix, y + 124, inner, 200, "Volume (fader). Move the fader to the level shown here and it takes over.")
  local tips = { "Mute the track.", "Hold Solo and press this strip's Mute to solo the track.", REC_MODES[S.rec_mode].label .. ". Rec button, acts on release." }
  for f = 1, 3 do tip_zone("tp_f" .. f .. "_" .. i, ix + (f - 1) * (fw + 4), y + 326, fw, 22, tips[f]) end
  label(ix, y + 354, tinfo[2], L(tinfo[1]) .. (S.manual[i] and "*" or ""))
  R.ImGui_DrawList_AddRect(dl, x, y, x + W, y + H, C.sep, 0, 0, 2)
end

-- master strip: volume (the master fader on the device), meters, mute
function draw_master(dl, x, y)
  local W, H = G.W, G.H
  local PADX = 7
  local inner = W - 2 * PADX
  local ix = x + PADX
  local now = R.time_precise()
  local tr = R.GetMasterTrack(0)
  if not tr then return end
  R.ImGui_DrawList_AddRectFilled(dl, x, y, x + W, y + H, C.strip, 0)
  R.ImGui_DrawList_AddRectFilled(dl, x, y, x + W, y + 3, C.pan, 0)
  R.ImGui_DrawList_AddRectFilled(dl, x, y + 3, x + W, y + 47, C.header, 0)
  R.ImGui_DrawList_AddText(dl, ix, y + 9, C.text, L("MASTER"))
  R.ImGui_DrawList_AddText(dl, ix, y + 26, C.dim, L(S.bank_down and S.bank_down[1] and "layer: Bank R" or "master fader"))
  -- master pan (hold Bank Right + a bottom knob on the device)
  local pan = info(tr, "D_PAN")
  local ptxt = math.abs(pan) < 0.005 and "C" or string.format("%s%d", pan < 0 and "L" or "R", math.floor(math.abs(pan) * 100 + 0.5))
  R.ImGui_DrawList_AddRectFilled(dl, ix, y + 53, ix + inner, y + 67, C.bar_bg, 2)
  local norm = clamp((pan + 1) / 2, 0, 1)
  local mid, px = ix + inner / 2, ix + inner * norm
  if px >= mid then R.ImGui_DrawList_AddRectFilled(dl, mid, y + 53, math.max(px, mid + 1), y + 67, C.pan, 2)
  else R.ImGui_DrawList_AddRectFilled(dl, px, y + 53, mid, y + 67, C.pan, 2) end
  R.ImGui_DrawList_AddLine(dl, mid, y + 53, mid, y + 67, 0xFFFFFF55, 1)
  local ptw = R.ImGui_CalcTextSize(ctx, ptxt)
  R.ImGui_DrawList_AddText(dl, mid - ptw / 2, y + 53, C.text, ptxt)
  draw_fader_area(dl, ix, inner, y, tr, 0xCCCCCCFF, true, now)
  -- M and S buttons
  local fw = (inner - 4) / 2
  for f, flag in ipairs({ { "M", info(tr, "B_MUTE") ~= 0, C.m_on }, { "S", info(tr, "I_SOLO") ~= 0, C.s_on } }) do
    local fx = ix + (f - 1) * (fw + 4)
    R.ImGui_DrawList_AddRectFilled(dl, fx, y + 326, fx + fw, y + 348, flag[2] and flag[3] or C.flag_off, 3)
    local tw = R.ImGui_CalcTextSize(ctx, flag[1])
    R.ImGui_DrawList_AddText(dl, fx + fw / 2 - tw / 2, y + 330, flag[2] and text_on(flag[3]) or C.dim, flag[1])
  end
  tip_zone("tp_mpan", ix, y + 53, inner, 14, "Master pan: hold Bank Right and turn a bottom knob.")
  tip_zone("tp_mvol", ix, y + 124, inner, 200, "Master volume (Master fader).")
  tip_zone("tp_mm", ix, y + 326, fw, 22, "Master mute: hold Bank Right and press Mute.")
  tip_zone("tp_ms", ix + fw + 4, y + 326, fw, 22, "Master solo: hold Bank Right and press Solo.")
  R.ImGui_DrawList_AddRect(dl, x, y, x + W, y + H, C.sep, 0, 0, 2)
end

-- round knob: dark disc, ring that fills up to the value, white pointer. norm 0..1; centre = fill from the middle (pan)
function arc_line(dl, cx, cy, r, n0, n1, col, th)
  local a0, sweep = 0.75 * math.pi, 1.5 * math.pi
  local steps = math.max(1, math.ceil(math.abs(n1 - n0) * 24))
  local px, py
  for k = 0, steps do
    local a = a0 + (n0 + (n1 - n0) * k / steps) * sweep
    local qx, qy = cx + math.cos(a) * r, cy + math.sin(a) * r
    if px then R.ImGui_DrawList_AddLine(dl, px, py, qx, qy, col, th) end
    px, py = qx, qy
  end
end

function draw_knob(dl, cx, cy, r, norm, col, centre, off)
  norm = clamp(norm, 0, 1)
  R.ImGui_DrawList_AddCircleFilled(dl, cx, cy, r, C.bar_bg)
  arc_line(dl, cx, cy, r - 2, 0, 1, 0xFFFFFF22, 3)
  if not off then
    if centre then arc_line(dl, cx, cy, r - 2, 0.5, norm, col, 3) else arc_line(dl, cx, cy, r - 2, 0, norm, col, 3) end
    local a = 0.75 * math.pi + norm * 1.5 * math.pi
    R.ImGui_DrawList_AddLine(dl, cx + math.cos(a) * r * 0.2, cy + math.sin(a) * r * 0.2,
      cx + math.cos(a) * (r - 4), cy + math.sin(a) * (r - 4), 0xFFFFFFFF, 2)
  end
end

-- fader the way the MPC mixer draws it: thin slot, light cap with a red line, narrow cyan meters on the right
function draw_fader_mpc(dl, ix, inner, y, tr, master, now)
  local function label(tx, ty, col, str) R.ImGui_DrawList_AddText(dl, tx, ty, col, str) end
  local ay, ah = y + 132, 164
  local function ypos(norm) return ay + ah - 2 - clamp(norm, 0, 1) * (ah - 4) end
  local cx = ix + 36
  local zy = ypos(norm_from_gain(1))
  R.ImGui_DrawList_AddRectFilled(dl, cx - 3, ay, cx + 3, ay + ah, C.bar_bg, 3)
  local last_y
  for _, t in ipairs(fader_ticks()) do
    local yy = ypos(norm_from_gain(10 ^ (t[1] / 20)))
    if t[1] ~= 0 and math.abs(yy - zy) >= 13 and (not last_y or math.abs(yy - last_y) >= 13) then
      R.ImGui_DrawList_AddLine(dl, ix + 22, yy, cx - 4, yy, 0xFFFFFF40, 1)
      label(ix, yy - 6, C.dim, t[2])
      last_y = yy
    end
  end
  if (CFG.fader_max_db or 12) >= 0 then
    R.ImGui_DrawList_AddLine(dl, ix + 20, zy, ix + inner, zy, C.zero, 1)
    label(ix, zy - 6, C.text, "0")
  end
  local m = meter_values(tr, now, master)
  for side = 0, 1 do
    local v = side == 0 and m.l or m.r
    local hv = side == 0 and m.hl or m.hr
    local x1 = ix + 54 + side * 8
    local top = ypos(norm_from_gain(math.max(v, 1e-5)))
    R.ImGui_DrawList_AddRectFilled(dl, x1, ay, x1 + 6, ay + ah, C.bar_bg, 0)
    if v > 0.00002 then R.ImGui_DrawList_AddRectFilled(dl, x1, top, x1 + 6, ay + ah - 2, C.mpc_meter, 0) end
    local ht = ypos(norm_from_gain(math.max(hv, 1e-5)))
    if hv > 0.00002 then R.ImGui_DrawList_AddRectFilled(dl, x1, ht - 1, x1 + 6, ht + 1, 0xFFFFFFFF, 0) end
  end
  local vol = info(tr, "D_VOL")
  local fy = ypos(norm_from_gain(vol))
  R.ImGui_DrawList_AddRectFilled(dl, cx - 12, fy - 7, cx + 12, fy + 7, C.mpc_cap, 3)
  R.ImGui_DrawList_AddLine(dl, cx - 12, fy, cx + 12, fy, C.akai, 2)
  local peak = math.max(m.hl, m.hr)
  local vt = db_text(vol)
  label(ix, y + 302, C.text, vt)
  local pt = (peak > 0.00002) and db_text(peak) or "-inf"
  local pw = R.ImGui_CalcTextSize(ctx, pt)
  label(ix + inner - pw, y + 302, peak > 1 and C.bad or C.dim, pt)
end

-- M / S / R squares at the bottom of an MPC-style strip
function draw_flags_mpc(dl, ix, inner, y, flags, id)
  local n = #flags
  local fw = (inner - (n - 1) * 4) / n
  for f = 1, n do
    local fx = ix + (f - 1) * (fw + 4)
    local on = flags[f][2]
    R.ImGui_DrawList_AddRectFilled(dl, fx, y + 326, fx + fw, y + 348, on and flags[f][3] or C.flag_off, 3)
    local tw = R.ImGui_CalcTextSize(ctx, flags[f][1])
    R.ImGui_DrawList_AddText(dl, fx + fw / 2 - tw / 2, y + 330, on and text_on(flags[f][3]) or C.dim, flags[f][1])
    tip_zone("tp_" .. id .. f, fx, y + 326, fw, 22, flags[f][4])
  end
end

function pan_text(pan)
  return math.abs(pan) < 0.005 and "C" or string.format("%s%d", pan < 0 and "L" or "R", math.floor(math.abs(pan) * 100 + 0.5))
end

-- one channel strip, MPC 2.0 look: round pan and send knobs, a fader with a light cap, thin cyan meters
function draw_strip_mpc(dl, x, y, i, tr)
  local W, H = G.WM, G.H
  local PADX = 6
  local inner = W - 2 * PADX
  local ix = x + PADX
  local now = R.time_precise()
  local function label(tx, ty, col, str) R.ImGui_DrawList_AddText(dl, tx, ty, col, str) end
  local function centered(cx, ty, col, str)
    local tw = R.ImGui_CalcTextSize(ctx, str)
    label(cx - tw / 2, ty, col, str)
  end
  R.ImGui_DrawList_AddRectFilled(dl, x, y, x + W, y + H, C.strip, 0)
  if not tr then
    label(ix, y + 8, C.dim, tostring(S.first + i - 1 > S.nvis and "-" or i))
    R.ImGui_DrawList_AddRect(dl, x, y, x + W, y + H, C.sep, 0, 0, 2)
    return
  end
  local ty = S.types[i] or "audio"
  local tinfo = TYPE_INFO[ty] or TYPE_INFO.audio
  local _, name = R.GetTrackName(tr, "")
  local ncol = rgba(R.GetTrackColor(tr))
  local has_col = (R.GetTrackColor(tr) or 0) ~= 0
  local selected = info(tr, "I_SELECTED") ~= 0
  local num = tostring(S.first + i - 1)
  R.ImGui_DrawList_AddRectFilled(dl, x, y, x + W, y + 3, has_col and ncol or tinfo[2], 0)
  local hcol = selected and ncol or C.header
  R.ImGui_DrawList_AddRectFilled(dl, x, y + 3, x + W, y + 41, hcol, 0)
  local fg = selected and text_on(ncol) or (has_col and lighten(ncol, 0.45) or C.text)
  type_icon(dl, ty, ix, y + 8, selected and text_on(ncol) or tinfo[2])
  label(ix + 22, y + 6, fg, num)
  label(ix, y + 22, fg, fit(name or "?", inner))
  R.ImGui_SetCursorScreenPos(ctx, x, y + 3)
  if R.ImGui_InvisibleButton(ctx, "type" .. i, W, 22) then cycle_type(i) end
  if R.ImGui_SetItemTooltip then
    R.ImGui_SetItemTooltip(ctx, L(tinfo[1]) .. L(S.manual[i] and " (set by hand)" or " (automatic)") .. L(". Click to change."))
  end
  if ty == "separator" then
    centered(x + W / 2, y + H / 2 - 6, C.dim, L("not controlled"))
    R.ImGui_DrawList_AddRect(dl, x, y, x + W, y + H, C.sep, 0, 0, 2)
    return
  end
  -- knobs: pan (left), send level (right); width and send name as small text under them
  local pan = info(tr, "D_PAN")
  local kx1, kx2, ky, kr = ix + inner * 0.27, ix + inner * 0.73, y + 62, 13
  draw_knob(dl, kx1, ky, kr, (pan + 1) / 2, C.pan, true)
  centered(kx1, ky + kr + 3, C.text, pan_text(pan))
  local nsend = R.GetTrackNumSends(tr, 0)
  local k = send_index(tr)
  local sv = k and R.GetTrackSendInfo_Value(tr, 0, k, "D_VOL") or 0
  draw_knob(dl, kx2, ky, kr, k and norm_from_gain(sv) or 0, C.send, false, not k)
  centered(kx2, ky + kr + 3, k and C.text or C.dim, k and db_text(sv) or "-")
  local dest = k and dest_name(tr, k)
  local cnt = nsend == 0 and L("no sends") or string.format("%d/%d", k and (k + 1) or 0, nsend)
  label(ix, y + 98, k and C.send or C.dim, fit(dest or cnt, inner))
  if width_active(tr) then
    local width = info(tr, "D_WIDTH")
    label(ix, y + 112, C.wid, string.format("W %d", math.floor(width * 100 + 0.5)))
  else
    label(ix, y + 112, C.dim, "W -")
  end
  draw_fader_mpc(dl, ix, inner, y, tr, false, now)
  draw_flags_mpc(dl, ix, inner, y, {
    { "M", info(tr, "B_MUTE") ~= 0, C.m_on, "Mute the track." },
    { "S", info(tr, "I_SOLO") ~= 0, C.s_on, "Hold Solo and press this strip's Mute to solo the track." },
    { REC_MODES[S.rec_mode].letter, rec_state(tr), C.r_on, REC_MODES[S.rec_mode].label .. ". Rec button, acts on release." },
  }, "f" .. i .. "_")
  tip_zone("tp_pan" .. i, kx1 - kr, ky - kr, 2 * kr, 2 * kr + 14, "Pan (bottom knob).")
  tip_zone("tp_snd" .. i, kx2 - kr, ky - kr, 2 * kr, 2 * kr + 14, "Send level (top knob). Hold Rec and tap Send All for this track's next send.")
  tip_zone("tp_wid" .. i, ix, y + 112, inner, 13, "Width (middle knob). Only works on tracks in stereo pan mode.")
  tip_zone("tp_vol" .. i, ix, y + 128, inner, 170, "Volume (fader). Move the fader to the level shown here and it takes over.")
  label(ix, y + 354, tinfo[2], L(tinfo[1]) .. (S.manual[i] and "*" or ""))
  R.ImGui_DrawList_AddRect(dl, x, y, x + W, y + H, C.sep, 0, 0, 2)
end

function draw_master_mpc(dl, x, y)
  local W, H = G.WM, G.H
  local PADX = 6
  local inner = W - 2 * PADX
  local ix = x + PADX
  local tr = R.GetMasterTrack(0)
  if not tr then return end
  R.ImGui_DrawList_AddRectFilled(dl, x, y, x + W, y + H, C.strip, 0)
  R.ImGui_DrawList_AddRectFilled(dl, x, y, x + W, y + 3, C.pan, 0)
  R.ImGui_DrawList_AddRectFilled(dl, x, y + 3, x + W, y + 41, C.header, 0)
  R.ImGui_DrawList_AddText(dl, ix, y + 6, C.text, L("MASTER"))
  R.ImGui_DrawList_AddText(dl, ix, y + 22, C.dim, fit(L(S.bank_down and S.bank_down[1] and "layer: Bank R" or "master fader"), inner))
  local pan = info(tr, "D_PAN")
  local kx, ky, kr = x + W / 2, y + 62, 13
  draw_knob(dl, kx, ky, kr, (pan + 1) / 2, C.pan, true)
  local pt = pan_text(pan)
  R.ImGui_DrawList_AddText(dl, kx - R.ImGui_CalcTextSize(ctx, pt) / 2, ky + kr + 3, C.text, pt)
  draw_fader_mpc(dl, ix, inner, y, tr, true, R.time_precise())
  draw_flags_mpc(dl, ix, inner, y, {
    { "M", info(tr, "B_MUTE") ~= 0, C.m_on, "Master mute: hold Bank Right and press Mute." },
    { "S", info(tr, "I_SOLO") ~= 0, C.s_on, "Master solo: hold Bank Right and press Solo." },
  }, "m")
  tip_zone("tp_mpan", kx - kr, ky - kr, 2 * kr, 2 * kr + 14, "Master pan: hold Bank Right and turn a bottom knob.")
  tip_zone("tp_mvol", ix, y + 128, inner, 170, "Master volume (Master fader).")
  R.ImGui_DrawList_AddRect(dl, x, y, x + W, y + H, C.sep, 0, 0, 2)
end

function change_setting(item, v)
  SHOWN[item.key] = v
  R.SetExtState(SET_SEC, item.key, tostring(v), true)
  if item.live then
    CFG[item.key] = v
    if item.key == "highlight" or item.key == "scroll_mixer" then S.sp_dirty = true end
  end
end

function reset_settings()
  for _, item in ipairs(SCHEMA) do
    if item.key then
      R.SetExtState(SET_SEC, item.key, "", true)
      SHOWN[item.key] = BASE[item.key]
      if item.live then CFG[item.key] = BASE[item.key] end
    end
  end
  S.sp_dirty = true
end

-- colour per plugin instance (same plugin = same colour)
FX_COLORS = { 0x3FB6A8FF, 0x6C8EF5FF, 0xB07CF0FF, 0xF0A13DFF, 0xE5484DFF, 0x4CBF6BFF, 0xE8D44DFF, 0xE07AB8FF }
function fx_color(fxguid)
  local h = 0
  for ch in tostring(fxguid):gmatch(".") do h = (h * 31 + ch:byte()) % 1000003 end
  return FX_COLORS[h % #FX_COLORS + 1]
end

function draw_instrument()
  local CW, CH, LBL = G.W, 70, 54
  local sx, sy = R.ImGui_GetCursorScreenPos(ctx)
  local dl = R.ImGui_GetWindowDrawList(ctx)
  local now = R.time_precise()
  local blink = math.floor(now * 3) % 2 == 0
  for r, row in ipairs(ROWS) do
    local y = sy + (r - 1) * (CH + G.GAP)
    R.ImGui_DrawList_AddText(dl, sx, y + CH / 2 - 6, C.dim, L(ROW_NAMES[row]))
    for i = 1, CFG.bank_size do
      local bk = row .. i
      local x = sx + LBL + (i - 1) * (CW + G.GAP)
      R.ImGui_DrawList_AddRectFilled(dl, x, y, x + CW, y + CH, C.panel, 5)
      local b = resolve_bind(bk, now)
      local armed = S.learn_key == bk
      if b then
        local col = fx_color(b.labels.fxguid)
        R.ImGui_DrawList_AddRectFilled(dl, x, y, x + 5, y + CH, col, 3)
        R.ImGui_DrawList_AddText(dl, x + 10, y + 4, C.text, fit(b.labels.param or "?", CW - 30))
        R.ImGui_DrawList_AddText(dl, x + 10, y + 20, col, fit(b.labels.fx or "?", CW - 16))
        R.ImGui_DrawList_AddText(dl, x + 10, y + 34, C.dim, fit(b.labels.track or "?", CW - 16))
        local v = R.TrackFX_GetParamNormalized(b.tr, b.fx, b.param) or 0
        R.ImGui_DrawList_AddRectFilled(dl, x + 10, y + CH - 14, x + CW - 8, y + CH - 6, C.bar_bg, 3)
        R.ImGui_DrawList_AddRectFilled(dl, x + 10, y + CH - 14, x + 10 + (CW - 18) * clamp(v, 0, 1), y + CH - 6, col, 3)
        R.ImGui_DrawList_AddText(dl, x + CW - 14, y + 3, C.dim, "x")
      else
        R.ImGui_DrawList_AddText(dl, x + 10, y + CH / 2 - 6, C.dim, L(armed and "touch a parameter" or "empty"))
      end
      if armed then
        R.ImGui_DrawList_AddRect(dl, x, y, x + CW, y + CH, blink and C.paused or C.dim, 5, 0, 2)
      end
      R.ImGui_SetCursorScreenPos(ctx, x, y)
      if R.ImGui_InvisibleButton(ctx, "cell" .. bk, CW - 18, CH) then
        if armed then S.learn_key = nil else start_learn(bk) end
      end
      if b then
        R.ImGui_SetCursorScreenPos(ctx, x + CW - 18, y)
        if R.ImGui_InvisibleButton(ctx, "clr" .. bk, 18, 18) then clear_bind(bk) end
      end
    end
  end
  R.ImGui_SetCursorScreenPos(ctx, sx, sy + 3 * (CH + G.GAP))
  R.ImGui_Dummy(ctx, LBL + CFG.bank_size * (CW + G.GAP) - G.GAP, 4)
  local ch, v = R.ImGui_Checkbox(ctx, L("Learn mode (turn a knob, then touch a parameter)") .. "##learn", S.learn_mode)
  if ch and v ~= nil then S.learn_mode = v; if not v then S.learn_key = nil end end
  R.ImGui_SameLine(ctx)
  if R.ImGui_Button(ctx, L("Clear all") .. "##clearall") then
    for _, row in ipairs(ROWS) do for i = 1, 8 do if S.binds[row .. i] then clear_bind(row .. i) end end end
  end
  R.ImGui_TextColored(ctx, C.dim, L("Click a cell, then touch a plugin parameter. Click x to forget a mapping, or hold Solo and turn its knob on the device. Mute opens the plugin window, Rec selects the track."))
end

function draw_settings()
  local width = CFG.bank_size * (G.W + G.GAP) - G.GAP
  R.ImGui_Dummy(ctx, width, 1)
  local need_restart, grp_pending, cur_grp = false, {}, nil
  for _, item in ipairs(SCHEMA) do
    if item.group then cur_grp = item.group
    elseif item.key and not item.live and SHOWN[item.key] ~= CFG[item.key] then
      need_restart = true
      grp_pending[cur_grp or ""] = true
    end
  end
  local section_open, first_group = true, true
  for _, item in ipairs(SCHEMA) do
    if item.group then
      -- every group is a collapsible header (the first one starts open), so the tab stays short
      local fl = (first_group and R.ImGui_TreeNodeFlags_DefaultOpen) and R.ImGui_TreeNodeFlags_DefaultOpen() or 0
      first_group = false
      -- a closed group still tells you when one of its settings waits for a restart
      local title = L(item.group) .. (grp_pending[item.group] and ("   " .. L("(restart needed)")) or "") .. "##grp_" .. item.group
      section_open = R.ImGui_CollapsingHeader(ctx, title, fl) and true or false
    elseif section_open then
      local v, changed, nv = SHOWN[item.key], false, nil
      local id = L(item.label) .. "##" .. item.key
      if item.kind == "bool" then
        changed, nv = R.ImGui_Checkbox(ctx, id, v)
      elseif item.kind == "enum" then
        local cur = 1
        for k, o in ipairs(item.options) do if o == v then cur = k end end
        if R.ImGui_SetNextItemWidth then R.ImGui_SetNextItemWidth(ctx, 260) end
        local ch, idx = R.ImGui_Combo(ctx, id, cur - 1, (function() local nm = {}; for k, n in ipairs(item.names) do nm[k] = L(n) end; return table.concat(nm, "\0") .. "\0" end)())
        if ch and idx ~= nil then changed, nv = true, item.options[idx + 1] end
      else
        if R.ImGui_SetNextItemWidth then R.ImGui_SetNextItemWidth(ctx, 200) end
        if item.kind == "int" then
          changed, nv = R.ImGui_SliderInt(ctx, id, v, item.min, item.max)
        else
          changed, nv = R.ImGui_SliderDouble(ctx, id, v, item.min, item.max, "%.1f")
        end
      end
      if changed and nv ~= nil then change_setting(item, nv) end
      if item.tip and R.ImGui_SetItemTooltip then R.ImGui_SetItemTooltip(ctx, L(item.tip)) end
      if not item.live then
        R.ImGui_SameLine(ctx)
        local pending = SHOWN[item.key] ~= CFG[item.key]
        R.ImGui_TextColored(ctx, pending and C.paused or C.dim, L(pending and "restart the script to apply" or "(needs restart)"))
      end
    end
  end
  R.ImGui_Spacing(ctx)
  if need_restart then R.ImGui_TextColored(ctx, C.paused, L("Restart the script to apply the changed settings.")) end
  if R.ImGui_Button(ctx, L("Dump track info (midimix_tracks.txt)")) then dump_tracks() end
  if R.ImGui_Button(ctx, L("Reset to defaults")) then reset_settings() end
  R.ImGui_SameLine(ctx)
  R.ImGui_TextColored(ctx, C.dim, L("Saved in REAPER, overrides midimix_config.lua"))
  S.need_restart = need_restart
end

-- which folder every slot of the bank sits in: S.fold[i] = { name =, color =, level = } (refreshed once a second)
function update_folders(now)
  local key = S.sig
  if key == S.fold_key and now - (S.fold_t or -100) < 1 then return end
  S.fold_key, S.fold_t = key, now
  local want, any = {}, false
  for i = 1, CFG.bank_size do
    if S.slots[i] then want[S.slots[i]] = i; any = true end
  end
  S.fold = {}
  if not any then return end
  local stack, left = {}, 0
  for k in pairs(want) do left = left + 1 end
  for j = 0, R.CountTracks(0) - 1 do
    local tr = R.GetTrack(0, j)
    local i = want[tr]
    if i then
      local top = stack[#stack]
      if top then S.fold[i] = { name = select(2, R.GetTrackName(top, "")), color = R.GetTrackColor(top), level = #stack, g = guid(top) } end
      left = left - 1
    end
    local d = info(tr, "I_FOLDERDEPTH")
    if d > 0 then for _ = 1, d do stack[#stack + 1] = tr end
    elseif d < 0 then for _ = 1, -d do stack[#stack] = nil end end
    if left <= 0 then break end
  end
end

-- a coloured band above the strips that sit in the same folder, with the folder's name
function draw_folder_band(dl, sx, sy)
  local i = 1
  while i <= CFG.bank_size do
    local f = S.fold and S.fold[i]
    if f then
      local j = i
      while j < CFG.bank_size and S.fold[j + 1] and S.fold[j + 1].g == f.g do j = j + 1 end
      local x1 = sx + (i - 1) * (SW() + G.GAP)
      local x2 = sx + j * (SW() + G.GAP) - G.GAP
      local col = (f.color and f.color ~= 0) and rgba(f.color) or TYPE_INFO.folder[2]
      R.ImGui_DrawList_AddRectFilled(dl, x1, sy, x2, sy + 15, col, 4)
      type_icon(dl, "folder", x1 + 5, sy + 1.5, text_on(col))
      R.ImGui_DrawList_AddText(dl, x1 + 26, sy + 1, text_on(col), fit(tostring(f.name or "?"), x2 - x1 - 30))
      i = j + 1
    else
      i = i + 1
    end
  end
end

-- Help tab: what every control does
HELP = {
  { "Basics", {
    { "Faders", "Track volume (the Master fader sets the master volume)" },
    { "Bottom knobs", "Pan" },
    { "Middle knobs", "Width (only on tracks in stereo pan mode)" },
    { "Top knobs", "Send level (the send shown in the window)" },
    { "Mute", "Mute the track" },
    { "Rec", "Rec arm, send mute or FX bypass (Rec row mode), acts on release" },
    { "Hold Solo + Mute", "Solo that track" },
    { "Solo, short tap", "Solo the whole bank (tap again to restore)" },
    { "Solo + any Rec", "Apply Rec to the whole bank" },
    { "Solo + Send All", "Clear all solo" },
  } },
  { "Banks", {
    { "Bank Left / Bank Right", "Previous / next bank" },
    { "Hold Bank %s s, release", "Jump to the first / last bank" },
    { "Solo + Bank", "Move the bank by one track" },
  } },
  { "Master", {
    { "Hold Bank Right + Mute", "Mute the master" },
    { "Hold Bank Right + Solo", "Solo the master" },
    { "Hold Bank Right + bottom knob", "Master pan" },
  } },
  { "Sends and modes", {
    { "Hold Rec + Send All", "Next send of that track" },
    { "Send All, double tap", "Pause / resume the script" },
    { "Solo, double tap", "Rec row mode: Rec arm > Send mute > FX bypass" },
    { "Send All, single tap", "Instrument mode on / off (when 'Send All tap = next send of ALL tracks' is off)" },
  } },
  { "Instrument mode", {
    { "Instrument tab: click a cell", "Then touch a plugin parameter to map it" },
    { "Mute (a strip)", "Open / close that strip's plugin window" },
    { "Rec (a strip)", "Select the track" },
    { "Both Bank buttons", "Play / stop" },
    { "Solo + knob", "Forget that mapping" },
    { "Solo + Send All", "Go to the start of the project" },
  } },
  { "Optional (Settings > Knobs and faders)", {
    { "Hold Solo + middle knob", "Stereo pan for one track" },
    { "Both Bank buttons together", "Stereo pan for the whole bank" },
  } },
}

function draw_help(width)
  local col2 = 270
  R.ImGui_BeginChild(ctx, "helpscroll", width, G.H - 10)
  for _, sec in ipairs(HELP) do
    R.ImGui_TextColored(ctx, C.head, L(sec[1]))
    for _, row in ipairs(sec[2]) do
      local title = L(row[1])
      if title:find("%s", 1, true) then   -- the Bank hold time comes from the settings
        local sec = string.format("%g", CFG.bank_hold_s)
        if CFG.language == "ru" then sec = sec:gsub("%.", ",") end
        title = title:format(sec)
      end
      R.ImGui_Text(ctx, title)
      R.ImGui_SameLine(ctx, col2)
      R.ImGui_TextColored(ctx, C.dim, L(row[2]))
    end
    R.ImGui_Spacing(ctx)
  end
  R.ImGui_EndChild(ctx)
end

-- Russian text needs a font with Cyrillic glyphs: attach the system sans-serif font (ReaImGui 0.9 and 0.10 differ)
function setup_font()
  FONT = nil
  if CFG.language ~= "ru" or not R.ImGui_CreateFont or not R.ImGui_Attach then return end
  local newapi = false
  if R.ImGui_GetVersion then
    local _, _, rv = R.ImGui_GetVersion()
    local ma, mi = tostring(rv or ""):match("^(%d+)%.(%d+)")
    newapi = ma and (tonumber(ma) > 0 or tonumber(mi) >= 10) or false
  end
  local ok, f = pcall(function()
    local f = newapi and R.ImGui_CreateFont("sans-serif") or R.ImGui_CreateFont("sans-serif", 13)
    R.ImGui_Attach(ctx, f)
    return f
  end)
  if ok and f then FONT, FONT_NEW = f, newapi end
end

function push_font()
  FONT_PUSHED = false
  if not FONT then return end
  local ok = pcall(function()
    if FONT_NEW then R.ImGui_PushFont(ctx, FONT, 13) else R.ImGui_PushFont(ctx, FONT) end
  end)
  FONT_PUSHED = ok
end

function pop_font()
  if FONT_PUSHED then pcall(R.ImGui_PopFont, ctx); FONT_PUSHED = false end
end

function draw_gui()
  if not HAVE_GUI or not S.gui_open then return end
  if not strips_valid() then return end
  if not ctx then
    ctx = R.ImGui_CreateContext("AKAI MidiMix")
    setup_font()
  end
  local wflags = R.ImGui_WindowFlags_AlwaysAutoResize and R.ImGui_WindowFlags_AlwaysAutoResize() or 0
  if R.ImGui_WindowFlags_NoDocking then wflags = wflags | (R.ImGui_WindowFlags_NoDocking() or 0) end   -- never snap into REAPER's docker
  local pushed = 0                                       -- title bar in Akai Red
  if R.ImGui_PushStyleColor then
    for _, nm in ipairs({ "TitleBg", "TitleBgActive", "TitleBgCollapsed" }) do
      local col_fn = R["ImGui_Col_" .. nm]
      if col_fn then
        R.ImGui_PushStyleColor(ctx, col_fn(), nm == "TitleBgActive" and C.akai or C.akai_dim)
        pushed = pushed + 1
      end
    end
  end
  push_font()
  local visible, open = R.ImGui_Begin(ctx, "AKAI MidiMix", true, wflags)
  if visible then
    local ok, err = pcall(function()
      -- status line
      local first, last = S.first, S.first
      for i = 1, CFG.bank_size do if S.slots[i] then last = S.first + i - 1 end end
      local state_col = not S.device_ok and C.bad or (S.enabled and C.ok or C.paused)
      local state = L(not S.device_ok and "NO DEVICE" or (S.enabled and "ACTIVE" or "PAUSED"))
      R.ImGui_TextColored(ctx, state_col, state)
      R.ImGui_SameLine(ctx)
      local nbanks = math.max(1, math.ceil(S.nvis / CFG.bank_size))
      local bank_no = math.min(nbanks, math.max(1, math.ceil(last / CFG.bank_size)))
      R.ImGui_TextColored(ctx, C.dim, CFG.global_sends and string.format(L("  bank %d/%d   tracks %d-%d / %d    send %d/%d"), bank_no, nbanks, first, last, S.nvis, S.send_page, S.page_count)
        or string.format(L("  bank %d/%d   tracks %d-%d / %d"), bank_no, nbanks, first, last, S.nvis))
      R.ImGui_SameLine(ctx)
      R.ImGui_TextColored(ctx, C.dim, L("  Mode:"))
      for _, md in ipairs({ { "mixer", "Mixer" }, { "instrument", "Instrument" } }) do
        R.ImGui_SameLine(ctx)
        if R.ImGui_RadioButton(ctx, L(md[2]) .. "##mode" .. md[1], S.mode == md[1]) then set_mode(md[1], R.time_precise()) end
      end
      R.ImGui_SameLine(ctx)
      R.ImGui_TextColored(ctx, C.dim, L("  Rec row:"))
      for m, mode in ipairs(REC_MODES) do
        R.ImGui_SameLine(ctx)
        if R.ImGui_RadioButton(ctx, L(mode.label) .. "##recmode" .. m, S.rec_mode == m) then
          set_rec_mode(m, R.time_precise())
        end
      end
      R.ImGui_SameLine(ctx)
      if R.ImGui_SmallButton(ctx, L(S.enabled and "Pause" or "Resume")) then toggle_enabled("window button") end
      R.ImGui_SameLine(ctx)
      if R.ImGui_SmallButton(ctx, L("Close script")) then S.quit = true end

      if R.ImGui_BeginTabBar(ctx, "tabs") then
        if R.ImGui_BeginTabItem(ctx, L("Mixer") .. "##tabmixer") then
         local okx, errx = pcall(function()
          local sx, sy = R.ImGui_GetCursorScreenPos(ctx)
          local dl = R.ImGui_GetWindowDrawList(ctx)
          update_folders(R.time_precise())
          pcall(draw_folder_band, dl, sx, sy)
          local sw = SW()
          local strip_fn = CFG.mixer_style == "mpc" and draw_strip_mpc or draw_strip
          local master_fn = CFG.mixer_style == "mpc" and draw_master_mpc or draw_master
          for i = 1, CFG.bank_size do
            local x = sx + (i - 1) * (sw + G.GAP)
            local ok2, err2 = pcall(strip_fn, dl, x, sy + 20, i, S.slots[i])
            if not ok2 and not S.gui_err_shown then
              S.gui_err_shown = true
              report_error("window", err2)
            end
          end
          local mxx = sx + CFG.bank_size * (sw + G.GAP) + G.PAD
          local okm, errm = pcall(master_fn, dl, mxx, sy + 20)
          if not okm and not S.gui_err_shown then
            S.gui_err_shown = true
            report_error("window", errm)
          end
          R.ImGui_SetCursorScreenPos(ctx, sx, sy)
          if CFG.mixer_style == "mpc" then   -- the teal bar under the MPC mixer
            R.ImGui_DrawList_AddRectFilled(dl, sx, sy + 20 + G.H + 3, mxx + sw, sy + 20 + G.H + 6, C.mpc_meter, 0)
          end
          R.ImGui_SetCursorScreenPos(ctx, sx, sy)
          R.ImGui_Dummy(ctx, CFG.bank_size * (sw + G.GAP) + G.PAD + sw, G.H + 24)
         end)
          R.ImGui_EndTabItem(ctx)   -- always close the tab, even after an error
          if not okx then error(errx, 0) end
        end
        if R.ImGui_BeginTabItem(ctx, L("Help") .. "##tabhelp") then
          local okh, errh = pcall(draw_help, CFG.bank_size * (SW() + G.GAP) + G.PAD + SW())
          R.ImGui_EndTabItem(ctx)
          if not okh then error(errh, 0) end
        end
        if R.ImGui_BeginTabItem(ctx, L("Instrument") .. "##tabinstr") then
          local ok4, err4 = pcall(draw_instrument)
          R.ImGui_EndTabItem(ctx)
          if not ok4 then error(err4, 0) end
        end
        if R.ImGui_BeginTabItem(ctx, L("Settings") .. "##tabset") then
          local ok3, err3 = pcall(draw_settings)
          R.ImGui_EndTabItem(ctx)
          if not ok3 then error(err3, 0) end
        end
        R.ImGui_EndTabBar(ctx)
      end
    end)
    R.ImGui_End(ctx)
    if pushed > 0 then R.ImGui_PopStyleColor(ctx, pushed) end
    pop_font()
    if not ok then error(err, 0) end
  else
    if pushed > 0 then R.ImGui_PopStyleColor(ctx, pushed) end
    pop_font()
  end
  if not open then S.gui_open = false end
end
