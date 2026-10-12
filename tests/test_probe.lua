local mock = dofile("tests/mock_reaper.lua")
local R, st = mock.new({ resource_path = "/tmp" })
_G.reaper = R
dofile("MIDI/AKAI MidiMix probe.lua")
st.run(0.2)
-- диоды: 30 нот * 0.4 с
st.run(13)
local lit = {}
for _, m in ipairs(st.out) do if m[3] == 127 then lit[m[2]] = true end end
local n = 0; for _ in pairs(lit) do n = n + 1 end
print("зажжено разных нот:", n)
st.note_on(1); st.run(0.1); st.note_off(1); st.run(0.1)
st.cc(19, 64); st.run(0.1)
st.push(0x90, 1, 127, 0); st.run(0.1)         -- чужое устройство
for i = 1, 20 do st.cc(30 + i, i) end st.run(0.1)
st.exit()
local text = table.concat(st.console)
for _, key in ipairs({ "NOTE ON", "NOTE OFF", "fader 1", "(other)", "DUMP", "mute 1", "probe stopped" }) do
  print(key, text:find(key, 1, true) and "ok" or "MISSING")
end
print("ошибки:", text:find("error: ", 1, true) and "YES" or "none")
