-- Scene for tests/render_preview.py: runs the real script against the REAPER mock, but records the ImGui
-- draw calls instead of painting them, so the preview shows exactly what the script draws.
-- Globals set by the caller: STYLE ("classic" | "mpc"), LANG ("en" | "ru"), measure(str) -> width in px.

local mock = dofile("tests/mock_reaper.lua")
local dir = "/tmp/mmrender_" .. STYLE .. "_" .. LANG
os.execute("mkdir -p " .. dir)
local f = io.open(dir .. "/midimix_config.lua", "w")
f:write(string.format('return { mixer_style = "%s", language = "%s", startup_anim = false }', STYLE, LANG))
f:close()

local R, st = mock.new({ gui = true, script_path = dir .. "/AKAI MidiMix.lua" })
_G.reaper = R

local function rgb(r, g, b) return r | (g << 8) | (b << 16) | 0x1000000 end
local drums = st.add_track("Drums", { I_FOLDERDEPTH = 1, color = rgb(224, 160, 60) })
local kick  = st.add_track("Kick",  { color = rgb(224, 160, 60), D_VOL = 0.9,  D_PAN = 0 })
local snare = st.add_track("Snare", { color = rgb(224, 160, 60), D_VOL = 0.7,  D_PAN = -0.15, I_SELECTED = 1 })
local hats  = st.add_track("Hats",  { color = rgb(224, 160, 60), D_VOL = 0.45, D_PAN = 0.35, I_FOLDERDEPTH = -1 })
local bass  = st.add_track("Bass",  { color = rgb(80, 150, 230), D_VOL = 1.2,  D_PAN = 0, instrument = true })
local lead  = st.add_track("Lead",  { color = rgb(170, 110, 235), D_VOL = 0.6, D_PAN = -0.5, instrument = true, I_PANMODE = 5, D_WIDTH = 0.8 })
local vox   = st.add_track("Vocal", { color = rgb(230, 90, 120), D_VOL = 0.8,  D_PAN = 0.1, I_RECARM = 1 })
local verb  = st.add_track("Reverb", { color = rgb(80, 190, 170), D_VOL = 0.5, B_MUTE = 0, recvs = { 1 } })
st.add_track("Pads", { color = rgb(120, 200, 120) })
st.add_send(kick, verb, 0.25); st.add_send(snare, verb, 0.5); st.add_send(lead, verb, 0.7); st.add_send(vox, verb, 0.9)
snare.B_MUTE = 0; hats.B_MUTE = 1; lead.I_SOLO = 0
local master = R.GetMasterTrack(0); master.D_VOL = 0.89; master.name = "master"

-- peaks differ per channel, set by the animation
st.pk = {}
R.Track_GetPeakInfo = function(t, ch) local p = st.pk[t.name]; return p and (ch == 0 and p[1] or p[2]) or 0 end

-- recorder instead of the painting ReaImGui
local cmds, tabs = {}, {}
local function c(s) cmds[#cmds + 1] = s end
local TABMAP = { ["##tabmixer"] = true }
setmetatable(R, { __index = function(_, name)
  if name:sub(1, 6) ~= "ImGui_" then return nil end
  return function(...)
    local a = { ... }
    if name == "ImGui_Begin" then cmds = {}; return true, true end
    if name == "ImGui_BeginTabBar" then return true end
    if name == "ImGui_BeginTabItem" then
      local label = tostring(a[2]):gsub("##.*$", "")
      local sel = tostring(a[2]):find("##tabmixer", 1, true) ~= nil
      c(string.format("tab\t%s\t%d", label, sel and 1 or 0))
      return sel
    end
    if name == "ImGui_GetCursorScreenPos" then return 8, 80 end
    if name == "ImGui_GetWindowDrawList" then return "dl" end
    if name == "ImGui_CalcTextSize" then return measure(tostring(a[2])), 13 end
    if name == "ImGui_TextColored" then c(string.format("w\ttext\t%d\t%s\t%d", a[2], tostring(a[3]), 0)) end
    if name == "ImGui_RadioButton" then c(string.format("w\tradio\t%d\t%s\t%d", a[3] and 1 or 0, (tostring(a[2]):gsub("##.*$", "")), 0)) return false end
    if name == "ImGui_SmallButton" then c(string.format("w\tbutton\t0\t%s\t0", (tostring(a[2]):gsub("##.*$", "")))) return false end
    if name == "ImGui_SameLine" then c("same") end
    if name == "ImGui_DrawList_AddRectFilled" then c(string.format("rectf\t%g\t%g\t%g\t%g\t%d\t%g", a[2], a[3], a[4], a[5], a[6], a[7] or 0)) end
    if name == "ImGui_DrawList_AddRect" then c(string.format("rect\t%g\t%g\t%g\t%g\t%d\t%g\t%g", a[2], a[3], a[4], a[5], a[6], a[7] or 0, a[9] or 1)) end
    if name == "ImGui_DrawList_AddLine" then c(string.format("line\t%g\t%g\t%g\t%g\t%d\t%g", a[2], a[3], a[4], a[5], a[6], a[7] or 1)) end
    if name == "ImGui_DrawList_AddCircleFilled" then c(string.format("circf\t%g\t%g\t%g\t%d", a[2], a[3], a[4], a[5])) end
    if name == "ImGui_DrawList_AddText" then c(string.format("text\t%g\t%g\t%d\t%s", a[2], a[3], a[4], tostring(a[5]))) end
    return nil
  end
end })

dofile("MIDI/AKAI MidiMix.lua")
st.run(1.6)

-- one animation step: moving meters, a moving fader and pan knob
local k = 0
function frame()
  k = k + 1
  local function pk(base, ph, sp) return base * (0.55 + 0.45 * math.abs(math.sin(k * sp + ph))) end
  st.pk = {
    Drums = { pk(0.8, 0, 0.35), pk(0.8, 0.3, 0.35) },
    Kick = { pk(0.95, 0.5, 0.52), pk(0.95, 0.5, 0.52) },
    Snare = { pk(0.8, 1.1, 0.41), pk(0.75, 1.3, 0.43) },
    Hats = { pk(0.5, 2.0, 0.6), pk(0.55, 2.2, 0.6) },
    Bass = { pk(0.7, 0.2, 0.3), pk(0.7, 0.2, 0.3) },
    Lead = { pk(0.8, 0.9, 0.22), pk(0.5, 1.4, 0.22) },
    Vocal = { pk(0.6, 1.7, 0.27), pk(0.65, 1.9, 0.27) },
    Reverb = { pk(0.4, 0.6, 0.18), pk(0.45, 0.8, 0.18) },
    master = { pk(0.85, 0.1, 0.33), pk(0.85, 0.4, 0.33) },
  }
  bass.D_VOL = 1.0 + 0.35 * math.sin(k * 0.12)
  lead.D_PAN = -0.6 * math.sin(k * 0.1)
  st.tick(0.08)
  local out = {}
  for i, s in ipairs(cmds) do out[i] = s end
  return out
end
