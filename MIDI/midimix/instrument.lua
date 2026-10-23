-- @noindex
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (c) 2026 The Eighth
-- MidiMix module: Instrument mode: learn and plugin parameter bindings. Loaded by AKAI MidiMix.lua into a shared environment.
-- Top-level names here are shared between modules (the 'local' keyword is dropped on purpose).

---------------------------------------------------------------------------
-- INSTRUMENT MODE: knobs control plugin parameters (own learn)
-- Bindings live in the project (ProjExtState), one per knob: "trackGUID|fxGUID|param index".
---------------------------------------------------------------------------
BIND_SEC = "MidiMixLua"
ROWS = { "top", "mid", "bot" }
ROW_NAMES = { top = "Top", mid = "Middle", bot = "Bottom" }

function tr_ok(tr) return tr and (not R.ValidatePtr2 or R.ValidatePtr2(0, tr, "MediaTrack*")) end

function load_binds()
  S.binds, S.bind_res = {}, {}
  S.binds_proj = R.EnumProjects and R.EnumProjects(-1) or nil
  if not R.GetProjExtState then return end
  for _, row in ipairs(ROWS) do
    for i = 1, 8 do
      local n, v = R.GetProjExtState(0, BIND_SEC, "bind_" .. row .. i)
      if n and n > 0 and type(v) == "string" then
        local tg, fg, pn = v:match("^(.-)|(.-)|(%d+)$")
        if tg then S.binds[row .. i] = { tguid = tg, fguid = fg, param = tonumber(pn) } end
      end
    end
  end
end

function save_bind(bk)
  local b = S.binds[bk]
  R.SetProjExtState(0, BIND_SEC, "bind_" .. bk, b and (b.tguid .. "|" .. b.fguid .. "|" .. b.param) or "")
  if R.MarkProjectDirty then R.MarkProjectDirty(0) end
  S.bind_res[bk] = nil
end

function clear_bind(bk)
  S.binds[bk] = nil
  save_bind(bk)
  S.picked["fx" .. bk] = nil
end

-- the live target of a binding: { tr, fx, param, labels } or nil (cached for one second)
function resolve_bind(bk, now)
  local b = S.binds[bk]
  if not b then return nil end
  now = now or R.time_precise()
  local r = S.bind_res[bk]
  if r and now - r.at < 1 and (not r.tr or tr_ok(r.tr)) then return r.tr and r or nil end
  r = { at = now }
  local tr = (b.tguid == "master") and R.GetMasterTrack(0) or find_track(b.tguid)
  if tr then
    for k = 0, R.TrackFX_GetCount(tr) - 1 do
      if R.TrackFX_GetFXGUID(tr, k) == b.fguid then r.fx = k; break end
    end
    if r.fx then
      r.tr, r.param = tr, b.param
      local _, tname = R.GetTrackName(tr, "")
      local _, fname = R.TrackFX_GetFXName(tr, r.fx, "")
      local _, pname = R.TrackFX_GetParamName(tr, r.fx, b.param, "")
      r.labels = { track = (b.tguid == "master") and "Master" or tname, fx = fname, param = pname, fxguid = b.fguid }
    end
  end
  S.bind_res[bk] = r
  return r.tr and r or nil
end

A.fxbind = {
  get = function(_, c) return R.TrackFX_GetParamNormalized(c.b.tr, c.b.fx, c.b.param) end,
  set = function(_, n, c) R.TrackFX_SetParamNormalized(c.b.tr, c.b.fx, c.b.param, n) end,
}

function strip_main_bind(i)
  for _, row in ipairs(ROWS) do
    local b = resolve_bind(row .. i)
    if b then return b end
  end
end

function set_mode(m, now)
  if S.mode == m then return end
  S.mode = m
  S.learn_key = nil
  reset_picks()
  S.mode_flash = { row = (m == "instrument") and "mute" or "rec", t_end = (now or R.time_precise()) + 0.5 }
  dbg("mode ->", m)
end
function toggle_mode(now) set_mode(S.mode == "mixer" and "instrument" or "mixer", now) end

function last_touched()
  if not R.GetLastTouchedFX then return nil end
  local ok, trn, fxn, pn = R.GetLastTouchedFX()
  if not ok then return nil end
  if math.floor(trn / 65536) ~= 0 or fxn < 0 or fxn >= 0x1000000 then return nil end  -- item FX / input FX: not supported
  return trn, fxn, pn
end
function track_by_number(trn)
  if trn == 0 then return R.GetMasterTrack(0) end
  return R.GetTrack(0, trn - 1)
end
function touched_value(trn, fxn, pn)
  local tr = track_by_number(trn)
  return tr and R.TrackFX_GetParamNormalized(tr, fxn, pn) or nil
end

function start_learn(bk)
  S.learn_key = bk
  local trn, fxn, pn = last_touched()
  S.learn_snap = { trn, fxn, pn, trn and touched_value(trn, fxn, pn) or nil }
  dbg("learn armed", bk)
end

function learn_tick(now)
  if not S.learn_key or now - (S.learn_poll or 0) < 0.08 then return end
  S.learn_poll = now
  local trn, fxn, pn = last_touched()
  if not trn then return end
  local snap = S.learn_snap or {}
  local val = touched_value(trn, fxn, pn)
  local changed = trn ~= snap[1] or fxn ~= snap[2] or pn ~= snap[3]
    or (val ~= nil and snap[4] ~= nil and math.abs(val - snap[4]) > 1e-6)
  if not changed then return end
  local tr = track_by_number(trn)
  if not tr then return end
  local bk = S.learn_key
  S.binds[bk] = { tguid = (trn == 0) and "master" or guid(tr), fguid = R.TrackFX_GetFXGUID(tr, fxn), param = pn }
  save_bind(bk)
  S.picked["fx" .. bk] = nil
  S.learn_key = nil
  dbg("learned", bk, S.binds[bk].tguid, S.binds[bk].fguid, pn)
end

-- is the plugin's floating window open? (REAPER gives nil or 0 when there is none, depending on the API version)
function fx_window_open(tr, fx)
  local w = R.TrackFX_GetFloatingWindow(tr, fx)
  return w ~= nil and w ~= false and w ~= 0
end

function inst_mute(i)
  local b = strip_main_bind(i)
  if not b then return end
  if fx_window_open(b.tr, b.fx) then R.TrackFX_Show(b.tr, b.fx, 2) else R.TrackFX_Show(b.tr, b.fx, 3) end
end
function inst_rec(i)
  local b = strip_main_bind(i)
  if not b then return end
  R.SetOnlyTrackSelected(b.tr)
  pcall(R.Main_OnCommand, 40913, 0)   -- scroll the selected track into view
end

function reload_binds_if_project_changed()
  if not R.EnumProjects then return end
  local p = R.EnumProjects(-1)
  if p ~= S.binds_proj then load_binds(); reset_picks() end
end
