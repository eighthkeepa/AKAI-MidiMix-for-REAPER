--[[
  @description MidiMix probe
  @version 0.1
  @author The Eighth
  @about Checks which notes and CCs the Akai MidiMix sends and lights its LEDs one by one.
  @changelog 0.1: first version

  MidiMix — пробный скрипт (разведка). Версия 0.1

  Что делает:
    1. Показывает список MIDI-устройств и находит MidiMix.
    2. Зажигает диоды по очереди (ноты 1..30), по 0.4 сек. Смотри, какие загораются.
    3. Печатает каждое событие от MidiMix: что нажато/повёрнуто, номер ноты/CC, значение.
    4. Замечает «дамп» (много CC подряд) — так ведёт себя кнопка Send All.
    5. Всё пишет в консоль REAPER и в файл midimix_probe_log.txt
       (папка ресурсов REAPER: Опции → Показать папку ресурсов).

  Перед запуском: Настройки → MIDI устройства. Включи MidiMix как вход
  (Enable input) и как выход (Enable output). «Enable input for control messages» не нужен.

  Что нажать по порядку (каждое — один раз, пауза между ними):
    mute 1, rec arm 1, mute 8, rec arm 8, Bank Left, Bank Right, Solo,
    Send All (коротко, потом подержать пару секунд),
    по одной ручке из каждого ряда у полосы 1 и 8, фейдер 1, фейдер 8, мастер-фейдер.
  Потом отправь мне файл midimix_probe_log.txt.

  Copyright (c) 2026 The Eighth. Licensed under the GNU GPL v3 or later (see LICENSE).
]]

local R = reaper
local MATCH = "midi%s*mix"

local log_path = R.GetResourcePath() .. "/midimix_probe_log.txt"
local f = io.open(log_path, "w")
local function out(s)
  R.ShowConsoleMsg(s .. "\n")
  if f then f:write(s .. "\n"); f:flush() end
end

-- Заводские значения, чтобы подписывать события
local known = {}
do
  local m = {
    fader = { 19, 23, 27, 31, 49, 53, 57, 61 },
    top = { 16, 20, 24, 28, 46, 50, 54, 58 },
    mid = { 17, 21, 25, 29, 47, 51, 55, 59 },
    bot = { 18, 22, 26, 30, 48, 52, 56, 60 },
    mute = { 1, 4, 7, 10, 13, 16, 19, 22 },
    rec = { 3, 6, 9, 12, 15, 18, 21, 24 },
  }
  for i = 1, 8 do
    known["cc" .. m.fader[i]] = "фейдер " .. i
    known["cc" .. m.top[i]] = "верхняя ручка " .. i
    known["cc" .. m.mid[i]] = "средняя ручка " .. i
    known["cc" .. m.bot[i]] = "нижняя ручка " .. i
    known["n" .. m.mute[i]] = "mute " .. i
    known["n" .. m.rec[i]] = "rec arm " .. i
  end
  known["cc62"] = "мастер-фейдер"
  known["n25"] = "Bank Left"
  known["n26"] = "Bank Right"
  known["n27"] = "Solo"
end

out("=== MidiMix probe v0.1 ===")
out(os.date("%Y-%m-%d %H:%M:%S"))

local in_ok, out_idx = {}, nil
local function dev_name(i)
  local ok, name = R.GetMIDIInputName(i, "")
  return ok and name or ("(устройство " .. tostring(i) .. ")")
end

out("-- Входы MIDI:")
for i = 0, R.GetNumMIDIInputs() - 1 do
  local ok, name = R.GetMIDIInputName(i, "")
  local hit = ok and name and name:lower():find(MATCH)
  out(string.format("  [%d] %s%s", i, tostring(name), hit and "   <== MidiMix" or ""))
  if hit then in_ok[i] = true end
end
out("-- Выходы MIDI:")
for i = 0, R.GetNumMIDIOutputs() - 1 do
  local ok, name = R.GetMIDIOutputName(i, "")
  local hit = ok and name and name:lower():find(MATCH)
  out(string.format("  [%d] %s%s", i, tostring(name), hit and "   <== MidiMix" or ""))
  if hit and out_idx == nil then out_idx = i end
end
if next(in_ok) == nil then
  out("!! Вход MidiMix не найден. Проверь подключение и Настройки → MIDI устройства.")
  out("   Если имя другое, поменяй MATCH в начале скрипта.")
end
if out_idx == nil then
  out("!! Выход MidiMix не найден: диоды проверить не получится.")
end

local function send(b1, b2, b3)
  if out_idx ~= nil then R.StuffMIDIMessage(16 + out_idx, b1, b2, b3) end
end

-- Тест диодов
local LED_FIRST, LED_LAST, LED_STEP = 1, 30, 0.4
local led_note, led_t = LED_FIRST - 1, R.time_precise()
local led_done = out_idx == nil
if not led_done then
  out("-- Тест диодов: смотри на устройство. Печатаю номер ноты, когда зажигаю.")
end

-- Чтение событий
local last_seq
do
  local seq = R.MIDI_GetRecentInputEvent(0)
  last_seq = (seq and seq > 0) and seq or 0
end
local burst = { t0 = -100, seen = {}, n = 0, shown = false }
local pressed = {}

local function describe(b1, b2, b3)
  local t, ch = b1 & 0xF0, (b1 & 0x0F) + 1
  if t == 0x90 and b3 > 0 then
    return string.format("НОТА ВКЛ   ch%d нота %-3d вел %-3d  %s", ch, b2, b3, known["n" .. b2] or "(?)"), "n" .. b2
  elseif t == 0x80 or (t == 0x90 and b3 == 0) then
    return string.format("НОТА ВЫКЛ  ch%d нота %-3d вел %-3d  %s", ch, b2, b3, known["n" .. b2] or "(?)"), "n" .. b2
  elseif t == 0xB0 then
    return string.format("CC         ch%d cc   %-3d знач %-3d  %s", ch, b2, b3, known["cc" .. b2] or "(?)"), "cc" .. b2
  end
  return string.format("ДРУГОЕ     байты %d %d %d", b1, b2 or -1, b3 or -1), nil
end

local function tick()
  local now = R.time_precise()

  -- диоды
  if not led_done and now - led_t >= LED_STEP then
    if led_note >= LED_FIRST then send(0x90, led_note, 0) end
    led_note = led_note + 1
    led_t = now
    if led_note > LED_LAST then
      led_done = true
      out("-- Тест диодов закончен. Теперь нажимай кнопки и крути ручки.")
    else
      send(0x90, led_note, 127)
      out("   диод: нота " .. led_note)
    end
  end

  -- события
  local evs = {}
  local newest
  for idx = 0, 4095 do
    local seq, buf, _, dev = R.MIDI_GetRecentInputEvent(idx)
    if not seq or seq == 0 then break end
    if idx == 0 then newest = seq end
    if seq <= last_seq then break end
    evs[#evs + 1] = { buf = buf, dev = dev }
  end
  if newest then last_seq = newest end

  for k = #evs, 1, -1 do
    local e = evs[k]
    if #e.buf >= 1 then
      local b1, b2, b3 = e.buf:byte(1, 3)
      local text, key = describe(b1, b2 or 0, b3 or 0)
      local mine = in_ok[e.dev] and "" or ("  [от другого устройства: " .. dev_name(e.dev) .. "]")
      if in_ok[e.dev] or next(in_ok) == nil then
        out(string.format("%8.3f  %s", now, text))
        -- пачка CC подряд
        if (b1 & 0xF0) == 0xB0 then
          if now - burst.t0 > 0.2 then burst = { t0 = now, seen = {}, n = 0, shown = false } end
          if not burst.seen[b2] then burst.seen[b2] = true; burst.n = burst.n + 1 end
          if burst.n >= 15 and not burst.shown then
            burst.shown = true
            out("   >>> ДАМП: " .. burst.n .. " разных CC за 0.2 сек (похоже на Send All)")
          end
        end
      else
        out(string.format("%8.3f  (чужое) %s%s", now, text, mine))
      end
    end
  end
end

local function loop()
  local ok, err = pcall(tick)
  if not ok then out("ошибка: " .. tostring(err)) end
  R.defer(loop)
end

R.atexit(function()
  for n = 0, 40 do send(0x90, n, 0) end
  out("=== probe остановлен ===")
  if f then f:close() end
end)

out("Запущено. Остановить: закрой окно скрипта или Actions → Terminate.")
loop()
