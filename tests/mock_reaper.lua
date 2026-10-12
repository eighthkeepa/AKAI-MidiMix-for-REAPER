-- Макет REAPER для проверки логики скрипта без настоящего REAPER.
-- Проверяет только нашу логику, а не то, как REAPER на самом деле ведёт себя.

local M = {}

function M.new(opts)
  opts = opts or {}
  local st = {
    tracks = {}, now = 100, defers = {}, atexits = {}, events = {}, seq = 0,
    out = {}, console = {}, ext = {}, toggles = {}, mixer_scroll = nil,
    in_names = opts.in_names or { "Other", "MIDI Mix" },
    out_names = opts.out_names or { "Other", "MIDI Mix" },
    dev_in = opts.dev_in or 1,
    script_path = opts.script_path or "/nonexistent/midimix_reaper.lua",
    spacer_works = opts.spacer_works ~= false,
    nextguid = 0, projext = {}, commands = {},
  }
  local R = {}
  st.R = R

  function st.add_track(name, props)
    st.nextguid = st.nextguid + 1
    local t = {
      guid = "{G" .. st.nextguid .. "}", name = name,
      D_VOL = 1, D_PAN = 0, D_WIDTH = 1, B_MUTE = 0, I_SOLO = 0, I_RECARM = 0,
      I_SPACER = 0, I_PANMODE = 0, B_SHOWINMIXER = 1, color = 0, sends = {},
    }
    for k, v in pairs(props or {}) do t[k] = v end
    st.tracks[#st.tracks + 1] = t
    return t
  end
  function st.remove_track(t)
    for i, x in ipairs(st.tracks) do if x == t then table.remove(st.tracks, i) break end end
  end
  function st.add_send(t, dest, vol) t.sends[#t.sends + 1] = { dest = dest, D_VOL = vol or 1 } end

  -- MIDI-вход
  function st.push(b1, b2, b3, dev)
    st.seq = st.seq + 1
    table.insert(st.events, 1, { seq = st.seq, buf = string.char(b1, b2, b3), dev = dev or st.dev_in })
    if #st.events > 4096 then table.remove(st.events) end
  end
  function st.cc(cc, val, ch) st.push(0xB0 | (ch or 0), cc, val) end
  function st.note_on(n, ch) st.push(0x90 | (ch or 0), n, 127) end
  function st.note_off(n, ch) st.push(0x80 | (ch or 0), n, 0) end

  -- Ход времени: вызвать все defer-функции
  function st.tick(dt)
    st.now = st.now + (dt or 0.03)
    local list = st.defers
    st.defers = {}
    for _, f in ipairs(list) do f() end
  end
  function st.run(seconds, dt)
    dt = dt or 0.03
    local n = math.floor(seconds / dt + 0.5)
    for _ = 1, n do st.tick(dt) end
  end
  function st.exit() for _, f in ipairs(st.atexits) do f() end end

  -- LED: последнее состояние по нотам
  function st.led(note)
    local v
    for _, m in ipairs(st.out) do if m[2] == note then v = m[3] end end
    return v
  end

  R.get_action_context = function() return true, st.script_path, 0, 1234 end
  R.ShowConsoleMsg = function(s) st.console[#st.console + 1] = s end
  R.time_precise = function() return st.now end
  R.defer = function(f) st.defers[#st.defers + 1] = f end
  R.atexit = function(f) st.atexits[#st.atexits + 1] = f end

  R.GetNumMIDIInputs = function() return #st.in_names end
  R.GetMIDIInputName = function(i) return st.in_names[i + 1] ~= nil, st.in_names[i + 1] end
  R.GetNumMIDIOutputs = function() return #st.out_names end
  R.GetMIDIOutputName = function(i) return st.out_names[i + 1] ~= nil, st.out_names[i + 1] end
  R.MIDI_GetRecentInputEvent = function(idx)
    local e = st.events[idx + 1]
    if not e then return 0, "", 0, 0, 0, 0 end
    return e.seq, e.buf, 0, e.dev, 0, 0
  end
  R.StuffMIDIMessage = function(mode, a, b, c)
    st.out[#st.out + 1] = { a, b, c, mode }
  end

  R.CountTracks = function() return #st.tracks end
  R.GetTrack = function(_, i) return st.tracks[i + 1] end
  R.GetMasterTrack = function() st.master = st.master or { guid = "{MASTER}", D_VOL = 1, sends = {} }; return st.master end
  R.GetTrackGUID = function(t) return t.guid end
  R.GetTrackName = function(t) return true, t.name or "master" end
  R.GetTrackColor = function(t) return t.color or 0 end
  R.ColorFromNative = function(c) return c & 255, (c >> 8) & 255, (c >> 16) & 255 end
  R.GetMediaTrackInfo_Value = function(t, k)
    if k == "IP_TRACKNUMBER" then
      for i, x in ipairs(st.tracks) do if x == t then return i end end
      return 0
    end
    return t[k] or 0
  end
  R.InsertTrackAtIndex = function(idx)
    st.nextguid = st.nextguid + 1
    local t = { guid = "{G" .. st.nextguid .. "}", name = "", D_VOL = 1, D_PAN = 0, D_WIDTH = 1, B_MUTE = 0, I_SOLO = 0,
                I_RECARM = 0, I_SPACER = 0, I_PANMODE = 0, B_SHOWINMIXER = 1, color = 0, sends = {} }
    table.insert(st.tracks, idx + 1, t)
  end
  R.DeleteTrack = function(t) st.remove_track(t) end
  R.ColorToNative = function(r, g, b) return r | (g << 8) | (b << 16) end
  R.SetMediaTrackInfo_Value = function(t, k, v)
    if k == "I_SPACER" and not st.spacer_works then return end
    t[k] = v
  end
  R.CSurf_OnVolumeChange = function(t, v) t.D_VOL = v; return v end
  R.CSurf_OnPanChange = function(t, v) t.D_PAN = v; return v end
  R.CSurf_OnWidthChange = function(t, v) t.D_WIDTH = v; return v end
  R.CSurf_OnMuteChange = function(t, v) t.B_MUTE = v; return v end
  R.CSurf_OnRecArmChange = function(t, v) t.I_RECARM = v; return v end
  R.CSurf_OnSendVolumeChange = function(t, k, v) t.sends[k + 1].D_VOL = v; return v end
  R.GetTrackNumSends = function(t, cat) if cat == -1 then return #(t.recvs or {}) end return #t.sends end
  R.GetSetMediaTrackInfo_String = function(t, k, v, set)
    t.strs = t.strs or {}
    if set then
      if k == "P_NAME" then t.name = v end
      t.strs[k] = v; return true, v
    end
    return true, t.strs[k] or ""
  end
  R.MarkProjectDirty = function() end
  R.Track_GetPeakInfo = function(t, ch) return (st.peak and st.peak[t.name]) or 0 end
  R.CountTrackMediaItems = function(t) return t.items or 0 end
  R.TrackFX_GetCount = function(t) return t.fxlist and #t.fxlist or (t.fx or 0) end
  R.TrackFX_GetFXGUID = function(t, k) return t.fxlist[k + 1].guid end
  R.TrackFX_GetFXName = function(t, k) return true, t.fxlist[k + 1].name end
  R.TrackFX_GetParamName = function(t, k, p) return true, t.fxlist[k + 1].params[p + 1].name end
  R.TrackFX_GetParamNormalized = function(t, k, p) return t.fxlist[k + 1].params[p + 1].val end
  R.TrackFX_SetParamNormalized = function(t, k, p, v) t.fxlist[k + 1].params[p + 1].val = v; return true end
  R.TrackFX_GetFloatingWindow = function(t, k) return t.fxlist[k + 1].window and "hwnd" or nil end
  R.TrackFX_Show = function(t, k, flag) t.fxlist[k + 1].window = (flag == 3) end
  R.GetLastTouchedFX = function()
    if not st.touched then return false end
    return true, st.touched[1], st.touched[2], st.touched[3]
  end
  R.EnumProjects = function() return "proj" end
  R.GetProjExtState = function(_, sec, key) local v = st.projext[sec .. "/" .. key]; return v and #v or 0, v or "" end
  R.SetProjExtState = function(_, sec, key, v) st.projext[sec .. "/" .. key] = (v ~= "" and v or nil); return 0 end
  R.SetOnlyTrackSelected = function(t) for _, x in ipairs(st.tracks) do x.I_SELECTED = 0 end; t.I_SELECTED = 1; st.selected = t end
  R.Main_OnCommand = function(cmd) st.commands[#st.commands + 1] = cmd end
  R.CSurf_GoStart = function() st.commands[#st.commands + 1] = "gostart" end
  R.TrackFX_GetInstrument = function(t) return t.instrument and 0 or -1 end
  R.GetSetTrackGroupMembership = function(t) return t.vca and 1 or 0 end
  R.GetTrackSendInfo_Value = function(t, _, k, name) if name == "P_DESTTRACK" then return t.sends[k + 1].dest end return t.sends[k + 1][name] or 0 end
  R.SetTrackSendInfo_Value = function(t, _, k, name, v) t.sends[k + 1][name] = v; return true end

  R.SetMixerScroll = function(t) st.mixer_scroll = t end
  R.GetMixerScroll = function() return st.mixer_scroll end
  R.TrackList_AdjustWindows = function() end
  R.UpdateArrange = function() end
  R.SetToggleCommandState = function(_, cmd, v) st.toggles[cmd] = v end
  R.RefreshToolbar2 = function() end
  R.GetExtState = function(sec, key) return st.ext[sec .. "/" .. key] or "" end
  R.SetExtState = function(sec, key, v) st.ext[sec .. "/" .. key] = v end
  R.GetResourcePath = function() return opts.resource_path or "/tmp" end

  -- Кривая фейдера: похожа по форме на REAPER, 12 дБ = 1000, 0 дБ около 630
  R.DB2SLIDER = function(db)
    local g = 10 ^ (db / 20)
    return 1000 * (g / 10 ^ (12 / 20)) ^ (1 / 3)
  end
  R.SLIDER2DB = function(s)
    if s <= 0 then return -150 end
    local g = 10 ^ (12 / 20) * (s / 1000) ^ 3
    return 20 * math.log(g, 10)
  end

  -- ReaImGui: заглушки, чтобы проверить, что код рисования не падает
  if opts.gui then
    st.gui_calls = 0
    setmetatable(R, {
      __index = function(_, name)
        if name:sub(1, 6) == "ImGui_" then
          return function(...)
            st.gui_calls = st.gui_calls + 1
            if name == "ImGui_Begin" then return true, true end
            if name == "ImGui_BeginTable" or name == "ImGui_BeginTabBar" or name == "ImGui_BeginTabItem" then return true end
            if name == "ImGui_Checkbox" or name == "ImGui_SliderInt" or name == "ImGui_SliderDouble" then
              local id, v = select(2, ...), nil
              if st.gui_set then v = st.gui_set[id] end
              if v ~= nil then return true, v end
              return false, (select(3, ...))
            end
            if name == "ImGui_GetCursorScreenPos" then return 100, 100 end
            if name == "ImGui_CalcTextSize" then return 6 * #tostring(select(2, ...) or ""), 13 end
            if name == "ImGui_GetWindowDrawList" then return "drawlist" end
            if name == "ImGui_DrawList_AddText" then
              st.gui_texts = st.gui_texts or {}
              st.gui_texts[#st.gui_texts + 1] = select(5, ...)
            end
            if name == "ImGui_Combo" then
              local id = select(2, ...)
              if st.gui_set and st.gui_set[id] ~= nil then return true, st.gui_set[id] end
              return false, select(3, ...)
            end
            if name == "ImGui_InvisibleButton" or name == "ImGui_RadioButton" then return st.gui_click == (select(2, ...)) end
            if name == "ImGui_Button" or name == "ImGui_SmallButton" then return st.gui_click == (select(2, ...)) end
            return nil
          end
        end
      end,
    })
  end

  return R, st
end

return M
