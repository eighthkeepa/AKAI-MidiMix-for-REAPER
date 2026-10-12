-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (c) 2026 The Eighth
-- MidiMix module: Adapters, banks, track types, rebuild, spacers, bank actions. Loaded by midimix_reaper.lua into a shared environment.
-- Top-level names here are shared between modules (the 'local' keyword is dropped on purpose).

---------------------------------------------------------------------------
-- PARAMETER ADAPTERS: get -> 0..1 or nil (no parameter), set(0..1)
---------------------------------------------------------------------------
rec_send_index = send_index

A = {}
A.fader = {
  get = function(tr) return norm_from_gain(info(tr, "D_VOL")) end,
  set = function(tr, n) set_vol(tr, gain_from_norm(n)) end,
}
A.master = A.fader
A.bot = { -- pan
  get = function(tr) return (info(tr, "D_PAN") + 1) / 2 end,
  set = function(tr, n)
    if math.abs(n - 0.5) <= CFG.center_snap / 127 then n = 0.5 end
    set_pan(tr, n * 2 - 1)
  end,
}
A.mid = { -- width (audible only in stereo pan; the mode is not checked: for tracks on the "default" mode I_PANMODE may return a different number)
  get = function(tr)
    return (info(tr, "D_WIDTH") + 1) / 2
  end,
  set = function(tr, n)
    if math.abs(n - 0.5) <= CFG.center_snap / 127 then n = 0.5 end
    set_width(tr, n * 2 - 1)
  end,
}
A.top = { -- send
  get = function(tr)
    local k = send_index(tr)
    if not k then return nil end
    return norm_from_gain(R.GetTrackSendInfo_Value(tr, 0, k, "D_VOL"))
  end,
  set = function(tr, n)
    local k = send_index(tr)
    if not k then return end
    local gain = gain_from_norm(n)
    if not pcall(R.CSurf_OnSendVolumeChange, tr, k, gain, false) then
      R.SetTrackSendInfo_Value(tr, 0, k, "D_VOL", gain)
    end
  end,
}

function track_for(c)
  if c.kind == "master" then return R.GetMasterTrack(0) end
  if c.kind == "fxbind" then return c.b.tr end
  return S.strips[c.strip]
end
function key_of(c)
  if c.bk then return "fx" .. c.bk end
  return c.kind .. (c.strip or "")
end

function reset_picks() S.picked = {}; S.last = {} end

---------------------------------------------------------------------------
-- BANK
---------------------------------------------------------------------------
function find_track(g)
  for i = 0, R.CountTracks(0) - 1 do
    local tr = R.GetTrack(0, i)
    if guid(tr) == g then return tr end
  end
end

function update_pages()
  local count = 1
  if CFG.sends_by_name then
    S.page_names = {}
    local seen = {}
    for i = 1, CFG.bank_size do
      local tr = S.strips[i]
      if tr then
        for k = 0, R.GetTrackNumSends(tr, 0) - 1 do
          local nm = dest_name(tr, k)
          if nm and not seen[nm] then seen[nm] = true; S.page_names[#S.page_names + 1] = nm end
        end
      end
    end
    count = math.max(1, #S.page_names)
  else
    for i = 1, CFG.bank_size do
      local tr = S.strips[i]
      if tr then count = math.max(count, R.GetTrackNumSends(tr, 0)) end
    end
  end
  S.page_count = count
  if S.send_page > count then S.send_page = 1; reset_picks() end
end

function safe(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, ...)
  if ok then return v end
  return nil
end

function is_separator_name(name)
  name = name or ""
  local low = name:lower()
  for _, pat in ipairs(CFG.separator_names) do
    if name:find(pat) or low:find(pat) then return true end
  end
  return false
end

-- Type chosen by hand (click the type label under a strip): stored in the track (P_EXT), saved with the project.
TYPE_ORDER = { "audio", "instrument", "bus", "vca", "folder", "separator" }
function read_override(tr)
  if not R.GetSetMediaTrackInfo_String then return nil end
  local ok, a, b = pcall(R.GetSetMediaTrackInfo_String, tr, "P_EXT:midimix_type", "", false)
  if not ok then return nil end
  local v = (type(a) == "string") and a or b
  if type(v) == "string" and v ~= "" then return v end
  return nil
end
function write_override(tr, v)
  if not R.GetSetMediaTrackInfo_String then return end
  pcall(R.GetSetMediaTrackInfo_String, tr, "P_EXT:midimix_type", v or "", true)
  if R.MarkProjectDirty then pcall(R.MarkProjectDirty, 0) end
end

function vca_flags(tr, which)  -- groups 1..32 and 33..64
  local lo = safe(R.GetSetTrackGroupMembership, tr, which, 0, 0) or 0
  local hi = safe(R.GetSetTrackGroupMembershipHigh, tr, which, 0, 0) or 0
  return lo, hi
end

-- theme layout names of a track (REAPER 7 themes have layouts such as "Separator", "Bus", "VCA")
function layout_of(tr, key)   -- key: "P_TCP_LAYOUT" or "P_MCP_LAYOUT"
  if not R.GetSetMediaTrackInfo_String then return "" end
  local ok, a, b = pcall(R.GetSetMediaTrackInfo_String, tr, key, "", false)
  if not ok then return "" end
  local v = (type(a) == "string") and a or b
  return type(v) == "string" and v or ""
end
function layout_type(tr)
  local names = (layout_of(tr, "P_TCP_LAYOUT") .. " " .. layout_of(tr, "P_MCP_LAYOUT")):lower()
  for _, t in ipairs({ "separator", "vca", "bus", "folder" }) do
    if names:find(t, 1, true) then return t end
  end
  return nil
end

-- audio | instrument | bus | vca | folder | separator  (cached for 1 s per track)
function compute_type(tr)
  local ov = read_override(tr)
  if ov then
    for _, t in ipairs(TYPE_ORDER) do if t == ov then return t, true end end
  end
  local lt = layout_type(tr)      -- the layout the user gave the track in REAPER
  if lt then return lt end
  local items = safe(R.CountTrackMediaItems, tr) or 0
  local fx = safe(R.TrackFX_GetCount, tr) or 0
  local sends = safe(R.GetTrackNumSends, tr, 0) or 0
  local recvs = safe(R.GetTrackNumSends, tr, -1) or 0
  local depth = info(tr, "I_FOLDERDEPTH")
  local empty = items == 0 and fx == 0 and sends == 0 and recvs == 0 and depth <= 0
  if empty then
    local _, name = R.GetTrackName(tr, "")
    if is_separator_name(name) then return "separator" end
    -- collapsed tracks in folders are small too, but they have no height override; a hand-made separator has one
    local h = info(tr, "I_HEIGHTOVERRIDE")
    if CFG.separator_max_h > 0 and h > 0 and h <= CFG.separator_max_h then return "separator" end
  end
  local lo, hi = vca_flags(tr, "VOLUME_VCA_MASTER")
  if lo ~= 0 or hi ~= 0 then return "vca" end
  if depth == 1 then return "folder" end
  local instr = (safe(R.TrackFX_GetInstrument, tr) or -1) >= 0
  if recvs > 0 and items == 0 and not instr then return "bus" end
  if instr then return "instrument" end
  return "audio"
end

function type_of(tr, now)
  local g = guid(tr)
  local c = S.tcache[g]
  if not c or now - c.at > 1 then
    local t, manual = compute_type(tr)
    c = { t = t, manual = manual, at = now }
    S.tcache[g] = c
  end
  return c.t, c.manual
end

function rebuild(now)
  S.last_rebuild = now
  local vis = {}
  for i = 0, R.CountTracks(0) - 1 do
    local tr = R.GetTrack(0, i)
    if (not CFG.mixer_visible_only or info(tr, "B_SHOWINMIXER") ~= 0)
       and not (S.markers.top and tr == S.markers.top.tr) and not (S.markers.bottom and tr == S.markers.bottom.tr)
       and not (CFG.skip_separators and type_of(tr, now) == "separator") then
      vis[#vis + 1] = tr
    end
  end
  local first = S.first
  if S.anchor_guid then
    for i, tr in ipairs(vis) do
      if guid(tr) == S.anchor_guid then first = i; break end
    end
  end
  first = clamp(first, 1, math.max(1, #vis))
  S.first, S.vis, S.nvis = first, vis, #vis
  S.anchor_guid = vis[first] and guid(vis[first]) or nil

  local ids = {}
  for i = 1, CFG.bank_size do
    local tr = vis[first + i - 1]
    local ty, manual = nil, nil
    if tr then ty, manual = type_of(tr, now) end
    S.slots[i], S.types[i], S.manual[i] = tr, ty, manual
    S.strips[i] = (ty ~= "separator") and tr or nil   -- a separator is never controlled
    ids[i] = tr and (guid(tr) .. (ty == "separator" and "~" or "")) or "-"
  end
  local sig = table.concat(ids, "|")
  if sig ~= S.sig then
    S.sig = sig
    S.sig_t = now
    reset_picks()
    S.sp_dirty = true
  end
  update_pages()
end

function scroll_mixer()
  S.scroll_set_at = R.time_precise()
  if CFG.scroll_mixer and S.slots[1] then pcall(R.SetMixerScroll, S.slots[1]) end
end

function move_bank_to(first)
  S.first = first
  S.anchor_guid = nil
  rebuild(R.time_precise())
  scroll_mixer()
end

function bank_page(dir)
  dbg("bank_page", dir, "first=", S.first, "nvis=", S.nvis)
  local new = S.first + dir * CFG.bank_size
  if dir > 0 and new > S.nvis then return end
  if new < 1 then new = 1 end
  if new ~= S.first then move_bank_to(new) end
end

function bank_jump(dir)
  local new = 1
  if dir > 0 then new = 1 + math.floor((math.max(1, S.nvis) - 1) / CFG.bank_size) * CFG.bank_size end
  dbg("bank_jump", dir, "first=", S.first, "->", new)
  if new ~= S.first then move_bank_to(new) end
end

function bank_nudge(dir)
  local new = clamp(S.first + dir, 1, math.max(1, S.nvis))
  if new ~= S.first then move_bank_to(new) end
end

---------------------------------------------------------------------------
-- SPACERS above and below the bank
---------------------------------------------------------------------------
function save_spacers()
  local ids = {}
  for g in pairs(S.sp_owned) do ids[#ids + 1] = g end
  R.SetExtState("MidiMixLua", "spacers", table.concat(ids, ","), true)
end

function tag_get(tr, key)
  if not R.GetSetMediaTrackInfo_String then return nil end
  local ok, a, b = pcall(R.GetSetMediaTrackInfo_String, tr, "P_EXT:" .. key, "", false)
  if not ok then return nil end
  local v = (type(a) == "string") and a or b
  if type(v) == "string" and v ~= "" then return v end
  return nil
end
function tag_set(tr, key, v)
  if R.GetSetMediaTrackInfo_String then pcall(R.GetSetMediaTrackInfo_String, tr, "P_EXT:" .. key, v or "", true) end
end

function cleanup_stale_spacers()
  -- anything we marked in the project earlier (crash, forced stop) is removed first
  for i = R.CountTracks(0) - 1, 0, -1 do
    local tr = R.GetTrack(0, i)
    local oc = tag_get(tr, "midimix_origcolor")
    if oc then set_info(tr, "I_CUSTOMCOLOR", tonumber(oc) or 0); tag_set(tr, "midimix_origcolor", "") end
    if tag_get(tr, "midimix_marker") then R.DeleteTrack(tr)
    elseif tag_get(tr, "midimix_spacer") then
      set_info(tr, "I_SPACER", 0)
      tag_set(tr, "midimix_spacer", "")
    end
  end
  local saved = R.GetExtState("MidiMixLua", "spacers")
  if saved and saved ~= "" then
    for g in saved:gmatch("[^,]+") do
      local tr = find_track(g)
      if tr then set_info(tr, "I_SPACER", 0) end
    end
    R.SetExtState("MidiMixLua", "spacers", "", true)
  end
end

function update_spacers()
  S.sp_dirty = false
  local want = {}
  if CFG.highlight == "spacers" and S.enabled and S.slots[1] then
    want[guid(S.slots[1])] = S.slots[1]
    local last_i = 0
    for i = 1, CFG.bank_size do if S.slots[i] then last_i = i end end
    local after = S.vis[S.first + last_i]
    if after then want[guid(after)] = after end
  end
  local changed = false
  for g in pairs(S.sp_owned) do
    if not want[g] then
      local tr = find_track(g)
      if tr then set_info(tr, "I_SPACER", 0); tag_set(tr, "midimix_spacer", "") end
      S.sp_owned[g] = nil
      changed = true
    end
  end
  for g, tr in pairs(want) do
    if not S.sp_owned[g] and info(tr, "I_SPACER") == 0 then
      set_info(tr, "I_SPACER", 1)
      tag_set(tr, "midimix_spacer", "1")
      if not S.sp_checked then
        S.sp_checked = true
        if info(tr, "I_SPACER") ~= 1 then
          say("spacers (I_SPACER) did not work, turning them off")
          CFG.highlight = "none"
          return
        end
      end
      S.sp_owned[g] = true
      changed = true
    end
  end
  if changed then
    save_spacers()
    R.TrackList_AdjustWindows(false)
    R.UpdateArrange()
  end
end

---------------------------------------------------------------------------
-- BUTTON ACTIONS
---------------------------------------------------------------------------
function each_strip(fn)
  for i = 1, CFG.bank_size do
    local tr = S.strips[i]
    if tr then fn(tr, i) end
  end
end

function bank_solo_toggle()
  local any, all = false, true
  each_strip(function(tr) any = true; if info(tr, "I_SOLO") == 0 then all = false end end)
  if not any then return end
  each_strip(function(tr) set_solo(tr, not all) end)
end

function bank_rec_toggle()
  local any, all = false, true
  each_strip(function(tr) any = true; if not rec_state(tr) then all = false end end)
  if not any then return end
  each_strip(function(tr) rec_set(tr, not all) end)
end

function clear_all_solo()
  for i = 0, R.CountTracks(0) - 1 do set_info(R.GetTrack(0, i), "I_SOLO", 0) end
end

function bank_stereo_pan()
  each_strip(function(tr) set_info(tr, "I_PANMODE", 5) end)
  reset_picks()
end

function next_page()
  S.send_page = S.send_page % S.page_count + 1
  S.tsend = {}  -- a global page change drops the per-track choices
  S.flash_page = S.send_page
  S.flash_until = R.time_precise() + CFG.page_flash_s
  reset_picks()
end

-- Next send of ONE track (strip number), independent of the other tracks.
function next_track_send(strip)
  local tr = S.strips[strip]
  if not tr then return end
  local n = R.GetTrackNumSends(tr, 0)
  if n == 0 then return end
  local cur = send_index(tr)
  local new = cur and (cur + 1) % n or 0
  S.tsend[guid(tr)] = new
  S.flash_page = new + 1
  S.flash_until = R.time_precise() + CFG.page_flash_s
  reset_picks()
  dbg("track send", strip, "->", new + 1, "of", n)
end

function set_toolbar()
  if SEC and CMD and CMD ~= 0 then
    R.SetToggleCommandState(SEC, CMD, S.enabled and 1 or 0)
    R.RefreshToolbar2(SEC, CMD)
  end
end

function toggle_enabled(why)
  dbg("toggle_enabled:", why or "?", "->", not S.enabled)
  S.enabled = not S.enabled
  S.solo_held, S.solo_used = false, false
  S.rec_held, S.rec_used = nil, false
  S.bank_down = { [-1] = false, [1] = false }
  S.bank_used = { [-1] = false, [1] = false }
  reset_picks()
  S.sp_dirty = true
  set_toolbar()
  dbg(S.enabled and "enabled" or "disabled (controller detached from tracks)")
end

