-- @noindex
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (c) 2026 The Eighth
-- MidiMix module: Window (ReaImGui). Loaded by midimix_reaper.lua into a shared environment.
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
  vol = 0x3FB6A8FF, pan = 0x6C8EF5FF, wid = 0xB07CF0FF, send = 0xF0A13DFF,
  m_on = 0xE8A33DFF, s_on = 0x4CBF6BFF, r_on = 0xE5484DFF, flag_off = 0x30333AFF,
  ok = 0x4CBF6BFF, paused = 0xE8A33DFF, bad = 0xE5484DFF,
}
G = { W = 104, GAP = 3, PAD = 6, H = 374 }

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
  for _, t in ipairs(fader_ticks()) do
    local yy = ypos(norm_from_gain(10 ^ (t[1] / 20)))
    if not last_y or math.abs(yy - last_y) >= 13 then
      R.ImGui_DrawList_AddLine(dl, sx1, yy, ix + inner, yy, 0xFFFFFF30, 1)
      label(ix, yy - 6, C.dim, t[2])
      last_y = yy
    end
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
    label(ix, y + 8, C.dim, tostring(S.first + i - 1 > S.nvis and "-" or i) .. "  (empty)")
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
    R.ImGui_SetItemTooltip(ctx, tinfo[1] .. (S.manual[i] and " (set by hand)" or " (automatic)") .. " - click to change")
  end

  if ty == "separator" then   -- never controlled
    local mw = R.ImGui_CalcTextSize(ctx, "not controlled")
    label(x + (W - mw) / 2, y + H / 2 - 6, C.dim, "not controlled")
    R.ImGui_DrawList_AddRect(dl, x, y, x + W, y + H, C.sep, 0, 0, 2)
    return
  end

  local pan = info(tr, "D_PAN")
  local ptxt = math.abs(pan) < 0.005 and "C" or string.format("%s%d", pan < 0 and "L" or "R", math.floor(math.abs(pan) * 100 + 0.5))
  bar(y + 53, 14, (pan + 1) / 2, C.pan, ptxt, true)
  local width = info(tr, "D_WIDTH")
  bar(y + 70, 12, (width + 1) / 2, C.wid, string.format("width %d", math.floor(width * 100 + 0.5)), true)

  -- send
  local nsend = R.GetTrackNumSends(tr, 0)
  local k = send_index(tr)
  if nsend == 0 then
    label(ix, y + 88, C.dim, "no sends")
    bar(y + 104, 12, 0, C.send, "-")
  else
    local count = string.format("%d/%d", k and (k + 1) or 0, nsend)
    local cw = R.ImGui_CalcTextSize(ctx, count)
    label(ix + inner - cw, y + 88, k and C.send or C.dim, count)
    local dest = k and dest_name(tr, k)
    label(ix, y + 88, k and C.text or C.dim, fit(dest or (k and "send" or "-"), inner - cw - 4))
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

  label(ix, y + 354, tinfo[2], tinfo[1] .. (S.manual[i] and "*" or ""))
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
  R.ImGui_DrawList_AddText(dl, ix, y + 9, C.text, "MASTER")
  R.ImGui_DrawList_AddText(dl, ix, y + 26, C.dim, "master fader")
  draw_fader_area(dl, ix, inner, y, tr, 0xCCCCCCFF, true, now)
  local mute = info(tr, "B_MUTE") ~= 0
  local fw = inner
  R.ImGui_DrawList_AddRectFilled(dl, ix, y + 326, ix + fw, y + 348, mute and C.m_on or C.flag_off, 3)
  local tw = R.ImGui_CalcTextSize(ctx, "M")
  R.ImGui_DrawList_AddText(dl, ix + fw / 2 - tw / 2, y + 330, mute and text_on(C.m_on) or C.dim, "M")
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
    R.ImGui_DrawList_AddText(dl, sx, y + CH / 2 - 6, C.dim, ROW_NAMES[row])
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
        R.ImGui_DrawList_AddText(dl, x + 10, y + CH / 2 - 6, C.dim, armed and "touch a parameter" or "empty")
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
  local ch, v = R.ImGui_Checkbox(ctx, "Learn mode (turn a knob, then touch a parameter)##learn", S.learn_mode)
  if ch and v ~= nil then S.learn_mode = v; if not v then S.learn_key = nil end end
  R.ImGui_SameLine(ctx)
  if R.ImGui_Button(ctx, "Clear all##clearall") then
    for _, row in ipairs(ROWS) do for i = 1, 8 do if S.binds[row .. i] then clear_bind(row .. i) end end end
  end
  R.ImGui_TextColored(ctx, C.dim, "Click a cell, then touch a plugin parameter. x = forget. On the device: hold Solo and turn a knob = forget it. Mute = plugin window, Rec = select the track.")
end

function draw_settings()
  local width = CFG.bank_size * (G.W + G.GAP) - G.GAP
  R.ImGui_Dummy(ctx, width, 1)
  local need_restart = false
  for _, item in ipairs(SCHEMA) do
    if item.group then
      R.ImGui_Spacing(ctx)
      R.ImGui_TextColored(ctx, C.dim, item.group)
    else
      local v, changed, nv = SHOWN[item.key], false, nil
      local id = item.label .. "##" .. item.key
      if item.kind == "bool" then
        changed, nv = R.ImGui_Checkbox(ctx, id, v)
      elseif item.kind == "enum" then
        local cur = 1
        for k, o in ipairs(item.options) do if o == v then cur = k end end
        if R.ImGui_SetNextItemWidth then R.ImGui_SetNextItemWidth(ctx, 260) end
        local ch, idx = R.ImGui_Combo(ctx, id, cur - 1, table.concat(item.names, "\0") .. "\0")
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
      if item.tip and R.ImGui_SetItemTooltip then R.ImGui_SetItemTooltip(ctx, item.tip) end
      if not item.live then
        R.ImGui_SameLine(ctx)
        local pending = SHOWN[item.key] ~= CFG[item.key]
        if pending then need_restart = true end
        R.ImGui_TextColored(ctx, pending and C.paused or C.dim, pending and "restart the script to apply" or "(needs restart)")
      end
    end
  end
  R.ImGui_Spacing(ctx)
  if R.ImGui_Button(ctx, "Dump track info (midimix_tracks.txt)") then dump_tracks() end
  if R.ImGui_Button(ctx, "Reset to defaults") then reset_settings() end
  R.ImGui_SameLine(ctx)
  R.ImGui_TextColored(ctx, C.dim, "Saved in REAPER, overrides midimix_config.lua")
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
      local x1 = sx + (i - 1) * (G.W + G.GAP)
      local x2 = sx + j * (G.W + G.GAP) - G.GAP
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

function draw_gui()
  if not HAVE_GUI or not S.gui_open then return end
  if not strips_valid() then return end
  if not ctx then
    ctx = R.ImGui_CreateContext("MidiMix")
  end
  local wflags = R.ImGui_WindowFlags_AlwaysAutoResize and R.ImGui_WindowFlags_AlwaysAutoResize() or 0
  local visible, open = R.ImGui_Begin(ctx, "MidiMix", true, wflags)
  if visible then
    local ok, err = pcall(function()
      -- status line
      local first, last = S.first, S.first
      for i = 1, CFG.bank_size do if S.slots[i] then last = S.first + i - 1 end end
      local state_col = not S.device_ok and C.bad or (S.enabled and C.ok or C.paused)
      local state = not S.device_ok and "NO DEVICE" or (S.enabled and "ACTIVE" or "PAUSED")
      R.ImGui_TextColored(ctx, state_col, state)
      R.ImGui_SameLine(ctx)
      local nbanks = math.max(1, math.ceil(S.nvis / CFG.bank_size))
      local bank_no = math.min(nbanks, math.max(1, math.ceil(last / CFG.bank_size)))
      R.ImGui_TextColored(ctx, C.dim, CFG.global_sends and string.format("  bank %d/%d   tracks %d-%d / %d    send %d/%d", bank_no, nbanks, first, last, S.nvis, S.send_page, S.page_count)
        or string.format("  bank %d/%d   tracks %d-%d / %d", bank_no, nbanks, first, last, S.nvis))
      R.ImGui_SameLine(ctx)
      R.ImGui_TextColored(ctx, C.dim, "  Mode:")
      for _, md in ipairs({ { "mixer", "Mixer" }, { "instrument", "Instrument" } }) do
        R.ImGui_SameLine(ctx)
        if R.ImGui_RadioButton(ctx, md[2] .. "##mode" .. md[1], S.mode == md[1]) then set_mode(md[1], R.time_precise()) end
      end
      R.ImGui_SameLine(ctx)
      R.ImGui_TextColored(ctx, C.dim, "  Rec row:")
      for m, mode in ipairs(REC_MODES) do
        R.ImGui_SameLine(ctx)
        if R.ImGui_RadioButton(ctx, mode.label .. "##recmode" .. m, S.rec_mode == m) then
          set_rec_mode(m, R.time_precise())
        end
      end
      R.ImGui_SameLine(ctx)
      if R.ImGui_SmallButton(ctx, S.enabled and "Pause" or "Resume") then toggle_enabled("window button") end
      R.ImGui_SameLine(ctx)
      if R.ImGui_SmallButton(ctx, "Close script") then S.quit = true end

      if R.ImGui_BeginTabBar(ctx, "tabs") then
        if R.ImGui_BeginTabItem(ctx, "Mixer") then
          local sx, sy = R.ImGui_GetCursorScreenPos(ctx)
          local dl = R.ImGui_GetWindowDrawList(ctx)
          update_folders(R.time_precise())
          pcall(draw_folder_band, dl, sx, sy)
          for i = 1, CFG.bank_size do
            local x = sx + (i - 1) * (G.W + G.GAP)
            local ok2, err2 = pcall(draw_strip, dl, x, sy + 20, i, S.slots[i])
            if not ok2 and not S.gui_err_shown then
              S.gui_err_shown = true
              report_error("window", err2)
            end
          end
          local mxx = sx + CFG.bank_size * (G.W + G.GAP) + G.PAD
          local okm, errm = pcall(draw_master, dl, mxx, sy + 20)
          if not okm and not S.gui_err_shown then
            S.gui_err_shown = true
            report_error("window", errm)
          end
          R.ImGui_SetCursorScreenPos(ctx, sx, sy)
          R.ImGui_Dummy(ctx, CFG.bank_size * (G.W + G.GAP) + G.PAD + G.W, G.H + 24)
          if R.ImGui_SetItemTooltip then R.ImGui_SetItemTooltip(ctx, "Click the type under a strip to set it by hand (* = manual). Cycles through all types, then back to automatic.") end
          R.ImGui_EndTabItem(ctx)
        end
        if R.ImGui_BeginTabItem(ctx, "Instrument") then
          local ok4, err4 = pcall(draw_instrument)
          R.ImGui_EndTabItem(ctx)
          if not ok4 then error(err4, 0) end
        end
        if R.ImGui_BeginTabItem(ctx, "Settings") then
          local ok3, err3 = pcall(draw_settings)
          R.ImGui_EndTabItem(ctx)
          if not ok3 then error(err3, 0) end
        end
        R.ImGui_EndTabBar(ctx)
      end
    end)
    R.ImGui_End(ctx)
    if not ok then error(err, 0) end
  end
  if not open then S.gui_open = false end
end
