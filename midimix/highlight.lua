-- MidiMix module: Bank highlight: markers, colours, mixer follow. Loaded by midimix_reaper.lua into a shared environment.
-- Top-level names here are shared between modules (the 'local' keyword is dropped on purpose).


---------------------------------------------------------------------------
-- MAIN LOOP
---------------------------------------------------------------------------
function track_index0(tr) return math.floor(info(tr, "IP_TRACKNUMBER") + 0.5) - 1 end

-- index just after the last track of a folder that starts at `tr` (or just after `tr` if it is not a folder)
function index_after(tr)
  local n = R.CountTracks(0)
  local j, depth = track_index0(tr), 0
  while j < n do
    depth = depth + info(R.GetTrack(0, j), "I_FOLDERDEPTH")
    if depth <= 0 then break end
    j = j + 1
  end
  return j + 1
end

function valid(tr) return tr and (not R.ValidatePtr2 or R.ValidatePtr2(0, tr, "MediaTrack*")) end

function remove_marker(which)
  local m = S.markers[which]
  S.markers[which] = nil
  if m and valid(m.tr) then
    R.DeleteTrack(m.tr)
    R.TrackList_AdjustWindows(false)
    S.sp_dirty = true
  end
end

function make_marker(which, idx, label)
  R.InsertTrackAtIndex(idx, false)
  local tr = R.GetTrack(0, idx)
  if not tr then return nil end
  local col = CFG.marker_color
  R.GetSetMediaTrackInfo_String(tr, "P_NAME", label, true)
  set_info(tr, "I_CUSTOMCOLOR", R.ColorToNative(col[1], col[2], col[3]) | 0x1000000)
  set_info(tr, "I_HEIGHTOVERRIDE", 23)
  set_info(tr, "B_MAINSEND", 0)
  -- look like a separator: take the layout of one of the user's own separator tracks, else the theme's "Separator"
  local tcp, mcp = "Separator", "Separator"
  for i = 0, R.CountTracks(0) - 1 do
    local o = R.GetTrack(0, i)
    if o ~= tr then
      local t1, m1 = layout_of(o, "P_TCP_LAYOUT"), layout_of(o, "P_MCP_LAYOUT")
      if (t1 .. m1):lower():find("separator", 1, true) then tcp, mcp = t1, m1; break end
    end
  end
  R.GetSetMediaTrackInfo_String(tr, "P_TCP_LAYOUT", tcp, true)
  R.GetSetMediaTrackInfo_String(tr, "P_MCP_LAYOUT", mcp, true)
  tag_set(tr, "midimix_marker", "1")
  return tr
end

-- two red separator tracks "MidiMix": one before the first track of the bank, one after the last (and after its folder)
function update_markers(now)
  for _, which in ipairs({ "top", "bottom" }) do
    local m = S.markers[which]
    if m and not valid(m.tr) then S.markers[which] = nil end
  end
  local first = S.slots[1]
  local last
  for i = 1, CFG.bank_size do if S.slots[i] then last = S.slots[i] end end
  if not (CFG.highlight == "markers" and S.enabled and first and last) then
    remove_marker("top"); remove_marker("bottom")
    return
  end
  local g1, g2 = guid(first), guid(last)
  local top, bot = S.markers.top, S.markers.bottom
  local top_ok = top and top.for_g == g1 and track_index0(top.tr) + 1 == track_index0(first)
  local bot_ok = bot and bot.for_g == g2 and track_index0(bot.tr) == index_after(last)
  if top_ok and bot_ok then return end
  if now - S.sig_t < 0.3 then return end          -- the bank is still moving
  remove_marker("top"); remove_marker("bottom")
  first, last = S.slots[1], nil
  for i = 1, CFG.bank_size do if S.slots[i] then last = S.slots[i] end end
  if not (first and last) then return end
  -- bottom first, so the index of the top one does not move
  local bi = index_after(last)
  local btr = make_marker("bottom", bi, "MidiMix \u{25B2}")
  if btr then S.markers.bottom = { tr = btr, for_g = guid(last) } end
  local ti = track_index0(first)
  local ttr = make_marker("top", ti, "MidiMix \u{25BC}")
  if ttr then S.markers.top = { tr = ttr, for_g = guid(first) } end
  R.TrackList_AdjustWindows(false)
  S.sp_dirty = true
end

-- tint the tracks of the bank; the original colour is kept in the track (P_EXT) and restored
function restore_color(g)
  local t = S.tinted[g]
  S.tinted[g] = nil
  if not t or not valid(t.tr) then return end
  if info(t.tr, "I_CUSTOMCOLOR") == t.set then set_info(t.tr, "I_CUSTOMCOLOR", t.orig) end  -- unless the user recoloured it meanwhile
  tag_set(t.tr, "midimix_origcolor", "")
  R.TrackList_AdjustWindows(false)
end

function update_colors(now)
  local want = {}
  if CFG.highlight == "color" and S.enabled then
    for i = 1, CFG.bank_size do
      local tr = S.strips[i]
      if tr then want[guid(tr)] = tr end
    end
  end
  for g in pairs(S.tinted) do if not want[g] then restore_color(g) end end
  local col, a = CFG.marker_color, clamp(CFG.highlight_tint, 0, 1)
  for g, tr in pairs(want) do
    if not S.tinted[g] then
      local orig = info(tr, "I_CUSTOMCOLOR")
      local r0, g0, b0 = 96, 96, 96                  -- tracks without their own colour: start from grey
      if orig ~= 0 then r0, g0, b0 = R.ColorFromNative(orig & 0xFFFFFF) end
      local nr = math.floor(r0 * (1 - a) + col[1] * a + 0.5)
      local ng = math.floor(g0 * (1 - a) + col[2] * a + 0.5)
      local nb = math.floor(b0 * (1 - a) + col[3] * a + 0.5)
      local new = R.ColorToNative(nr, ng, nb) | 0x1000000
      tag_set(tr, "midimix_origcolor", tostring(math.floor(orig)))
      set_info(tr, "I_CUSTOMCOLOR", new)
      S.tinted[g] = { tr = tr, orig = orig, set = new }
      R.TrackList_AdjustWindows(false)
    end
  end
end

function follow_mixer_scroll(now)
  if not CFG.follow_mixer or not R.GetMixerScroll or now - (S.scroll_poll or 0) < 0.25 then return end
  S.scroll_poll = now
  local tr = R.GetMixerScroll()
  if not tr or not R.ValidatePtr2 or not R.ValidatePtr2(0, tr, "MediaTrack*") then
    if not tr then return end
  end
  local g = guid(tr)
  if g == S.scroll_seen then return end
  S.scroll_seen = g
  if now - (S.scroll_set_at or -100) < 0.6 then return end   -- we scrolled it ourselves
  for i, t in ipairs(S.vis) do
    if t == tr then
      if i ~= S.first then
        S.first, S.anchor_guid = i, nil
        rebuild(now)
        S.scroll_set_at = now   -- do not scroll the mixer back
      end
      return
    end
  end
end
