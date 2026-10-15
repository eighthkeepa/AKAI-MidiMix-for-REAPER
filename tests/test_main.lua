-- Проверка логики AKAI MidiMix.lua на макете REAPER.
-- Запуск: python3 tests/run.py  (из папки проекта)

local mock = dofile("tests/mock_reaper.lua")
local passes, fails = 0, 0
local current = "?"

local function check(cond, msg)
  if cond then passes = passes + 1
  else fails = fails + 1; print("  ПРОВАЛ [" .. current .. "]: " .. msg) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local n_dir = 0
local function setup(opts)
  opts = opts or {}
  if opts.cfg then
    n_dir = n_dir + 1
    local dir = "/tmp/mmtest_" .. n_dir
    os.execute("mkdir -p " .. dir)
    local f = io.open(dir .. "/midimix_config.lua", "w")
    f:write(opts.cfg)
    f:close()
    opts.script_path = dir .. "/AKAI MidiMix.lua"
  end
  local R, st = mock.new(opts)
  _G.reaper = R
  for i = 1, (opts.tracks or 10) do st.add_track("T" .. i) end
  if opts.before then opts.before(st) end
  dofile("MIDI/AKAI MidiMix.lua")
  st.run(1.4)  -- the start-up LED circle takes ~1.1 s
  return st
end

local function no_errors(st)
  for _, line in ipairs(st.console) do
    if line:find("[Ee]rror") then check(false, "в консоли: " .. line) return end
  end
  check(true, "нет ошибок")
end

local function press(st, note, hold)
  st.note_on(note); st.run(hold or 0.06); st.note_off(note); st.run(0.06)
end
local function norm_of(db_gain_norm) return db_gain_norm end
-- ступень фейдера, соответствующая усилению 1 (0 дБ) в макете
local function step_for_gain(g)
  local R = _G.reaper
  return R.DB2SLIDER(20 * math.log(g, 10)) / R.DB2SLIDER(12) * 127
end

-- Номера по умолчанию
local MUTE = { 1, 4, 7, 10, 13, 16, 19, 22 }
local REC = { 3, 6, 9, 12, 15, 18, 21, 24 }
local FADER = { 19, 23, 27, 31, 49, 53, 57, 61 }
local TOP = { 16, 20, 24, 28, 46, 50, 54, 58 }
local MID = { 17, 21, 25, 29, 47, 51, 55, 59 }
local BOT = { 18, 22, 26, 30, 48, 52, 56, 60 }
local BL, BR, SOLO, SENDALL = 25, 26, 27, 28

local function test(name, fn) current = name; print("* " .. name); fn() end

---------------------------------------------------------------------------
test("старт: устройство найдено, диоды банка горят, остальные нет", function()
  local st = setup()
  check(st.led(BL) == 0 and st.led(BR) == 0, "на первом банке bank-диоды тёмные")
  check(st.led(MUTE[1]) == 0, "mute-диод выключен")
  check(st.toggles[1234] == 1, "кнопка панели включена")
  no_errors(st)
end)

test("mute и rec", function()
  local st = setup()
  press(st, MUTE[1])
  check(st.tracks[1].B_MUTE == 1, "трек 1 заглушён")
  check(st.led(MUTE[1]) == 127, "mute-диод горит")
  press(st, MUTE[1])
  check(st.tracks[1].B_MUTE == 0, "mute снят")
  press(st, REC[3])
  check(st.tracks[3].I_RECARM == 1, "rec трека 3")
  check(st.led(REC[3]) == 127, "rec-диод горит")
  no_errors(st)
end)

test("фейдер: подхват, потом управление", function()
  local st = setup()
  local zero = step_for_gain(1)
  st.cc(FADER[1], 5); st.run(0.1)
  check(near(st.tracks[1].D_VOL, 1), "далеко от значения: ничего не меняется")
  st.cc(FADER[1], 20); st.run(0.1)
  check(near(st.tracks[1].D_VOL, 1), "всё ещё до значения")
  st.cc(FADER[1], math.floor(zero) + 10); st.run(0.1)
  check(st.tracks[1].D_VOL ~= 1, "перешли значение: подхват сработал")
  local v1 = st.tracks[1].D_VOL
  st.cc(FADER[1], 40); st.run(0.1)
  check(st.tracks[1].D_VOL < v1, "дальше управляет")
  st.cc(FADER[1], 0); st.run(0.1)
  check(st.tracks[1].D_VOL == 0, "нижний край = тишина")
  no_errors(st)
end)

test("внешнее изменение в REAPER снова требует подхвата", function()
  local st = setup()
  local zero = math.floor(step_for_gain(1))
  st.cc(FADER[1], zero); st.run(0.1)           -- совпало, подхват
  st.cc(FADER[1], zero - 5); st.run(0.1)
  local v = st.tracks[1].D_VOL
  check(v < 1, "управляет")
  st.tracks[1].D_VOL = 2.0                    -- изменили мышью в REAPER
  st.run(0.2)
  st.cc(FADER[1], zero - 20); st.run(0.1)
  check(near(st.tracks[1].D_VOL, 2.0), "фейдер не трогает трек, пока не подхвачен")
end)

test("pan и ширина", function()
  local st = setup({ cfg = "return { allow_panmode_change = true }" })
  st.cc(BOT[1], 64); st.run(0.1)
  check(near(st.tracks[1].D_PAN, 0), "центр, прилипание")
  st.cc(BOT[1], 127); st.run(0.1)
  check(near(st.tracks[1].D_PAN, 1, 0.01), "pan вправо")
  -- ширина молчит вне stereo pan
  st.cc(MID[1], 127); st.run(0.1)
  check(st.tracks[1].D_WIDTH == 1, "ширина не меняется вне stereo pan")
  -- Solo + средняя ручка включает stereo pan (только если разрешено)
  st.note_on(SOLO); st.run(0.06)
  st.cc(MID[1], 100); st.run(0.1)
  st.note_off(SOLO); st.run(0.06)
  check(st.tracks[1].I_PANMODE == 5, "режим stereo pan включён")
  check(st.tracks[1].I_SOLO == 0, "а соло банка не сработало (Solo использован как Shift)")
  st.cc(MID[1], 127); st.run(0.1)
  st.cc(MID[1], 0); st.run(0.1)
  check(near(st.tracks[1].D_WIDTH, -1, 0.01), "ширина управляется")
  no_errors(st)
end)

test("скрипт сам не меняет режим pan (по умолчанию), ширина только в stereo pan", function()
  local st = setup()
  st.note_on(SOLO); st.run(0.06)
  st.cc(MID[1], 100); st.run(0.1)
  st.note_off(SOLO); st.run(0.06)
  check(st.tracks[1].I_PANMODE == 0, "Solo + средняя ручка не меняет режим pan")
  check(st.tracks[1].I_SOLO == 0, "Solo использован как Shift")
  st.cc(MID[1], 127); st.run(0.1); st.cc(MID[1], 0); st.run(0.1)
  check(st.tracks[1].D_WIDTH == 1, "ширина вне stereo pan не трогается")
  st.tracks[1].I_PANMODE = 5                       -- пользователь сам включил stereo pan
  st.cc(MID[1], 127); st.run(0.1); st.cc(MID[1], 0); st.run(0.1)
  check(near(st.tracks[1].D_WIDTH, -1, 0.01), "в stereo pan ширина управляется")
  no_errors(st)
  local st2 = setup({ cfg = "return { width_needs_stereo_pan = false }" })
  st2.cc(MID[1], 127); st2.run(0.1); st2.cc(MID[1], 0); st2.run(0.1)
  check(near(st2.tracks[1].D_WIDTH, -1, 0.01), "width_needs_stereo_pan = false: ширина везде")
  no_errors(st2)
end)

test("Solo + Mute: соло одного трека", function()
  local st = setup()
  st.note_on(SOLO); st.run(0.06)
  st.note_on(MUTE[2]); st.run(0.06); st.note_off(MUTE[2]); st.run(0.06)
  check(st.led(MUTE[2]) == 127, "пока держим Solo, диод показывает соло")
  check(st.led(MUTE[1]) == 0, "несолированный не горит")
  st.note_off(SOLO); st.run(0.06)
  check(st.tracks[2].I_SOLO == 2, "трек 2 в соло")
  check(st.tracks[1].I_SOLO == 0, "трек 1 нет")
  check(st.tracks[2].B_MUTE == 0, "mute не менялся")
  -- мигание
  local seen = {}
  for _ = 1, 40 do st.tick(0.05); seen[st.led(MUTE[2])] = true end
  check(seen[0] and seen[127], "диод солированного трека мигает")
  -- снять тем же способом
  st.note_on(SOLO); st.run(0.06)
  st.note_on(MUTE[2]); st.run(0.06); st.note_off(MUTE[2]); st.run(0.06)
  st.note_off(SOLO); st.run(0.06)
  check(st.tracks[2].I_SOLO == 0, "соло снято")
  no_errors(st)
end)

test("Solo коротко: соло всего банка, и обратно", function()
  local st = setup()
  press(st, SOLO)
  for i = 1, 8 do check(st.tracks[i].I_SOLO == 2, "трек " .. i .. " в соло") end
  check(st.tracks[9].I_SOLO == 0, "трек 9 вне банка")
  press(st, SOLO)
  for i = 1, 8 do check(st.tracks[i].I_SOLO == 0, "трек " .. i .. " снят") end
end)

test("Solo + Rec: rec на весь банк", function()
  local st = setup()
  st.note_on(SOLO); st.run(0.06)
  st.note_on(REC[4]); st.run(0.06); st.note_off(REC[4]); st.run(0.06)
  st.note_off(SOLO); st.run(0.06)
  for i = 1, 8 do check(st.tracks[i].I_RECARM == 1, "rec " .. i) end
  check(st.tracks[1].I_SOLO == 0, "соло не сработало")
  st.note_on(SOLO); st.run(0.06)
  st.note_on(REC[1]); st.run(0.06); st.note_off(REC[1]); st.run(0.06)
  st.note_off(SOLO); st.run(0.06)
  for i = 1, 8 do check(st.tracks[i].I_RECARM == 0, "rec снят " .. i) end
end)

test("банки: вправо, пустые полосы, влево, пробелы, прокрутка миксера", function()
  local st = setup({ tracks = 12 })
  check(st.tracks[1].I_SPACER == 1, "пробел над первым треком банка")
  check(st.tracks[9].I_SPACER == 1, "пробел под последним (над 9-м)")
  press(st, BR)
  check(st.mixer_scroll == st.tracks[9], "миксер прокручен к 9-му")
  check(st.tracks[1].I_SPACER == 0, "старый пробел снят")
  check(st.tracks[9].I_SPACER == 1, "пробел над 9-м")
  check(st.led(MUTE[5]) == 0 and st.led(REC[5]) == 0, "пустая полоса тёмная")
  press(st, MUTE[5])
  for i = 1, 12 do check(st.tracks[i].B_MUTE == 0, "пустая полоса ничего не делает") end
  press(st, MUTE[1])
  check(st.tracks[9].B_MUTE == 1, "первая полоса = 9-й трек")
  press(st, BR)
  check(st.mixer_scroll == st.tracks[9], "дальше края не уходим")
  press(st, BL)
  check(st.mixer_scroll == st.tracks[1], "назад к 1-му")
  check(st.tracks[1].I_SPACER == 1 and st.tracks[9].I_SPACER == 1, "пробелы вокруг первого банка")
  no_errors(st)
end)

test("Solo + Bank: сдвиг на 1 трек", function()
  local st = setup({ tracks = 12 })
  st.note_on(SOLO); st.run(0.06)
  st.note_on(BR); st.run(0.06); st.note_off(BR); st.run(0.06)
  st.note_off(SOLO); st.run(0.06)
  press(st, MUTE[1])
  check(st.tracks[2].B_MUTE == 1, "первая полоса = 2-й трек")
  check(st.tracks[1].I_SOLO == 0, "соло не сработало")
end)

test("обе Bank вместе: stereo pan всему банку (если разрешено)", function()
  local st = setup({ tracks = 12, cfg = "return { allow_panmode_change = true }" })
  st.note_on(BL); st.run(0.06)
  st.note_on(BR); st.run(0.06)
  st.note_off(BL); st.run(0.06); st.note_off(BR); st.run(0.06)
  for i = 1, 8 do check(st.tracks[i].I_PANMODE == 5, "stereo pan " .. i) end
  check(st.tracks[9].I_PANMODE == 0, "вне банка не тронут")
  press(st, MUTE[1])
  check(st.tracks[1].B_MUTE == 1, "банк остался на месте")
  check(st.mixer_scroll == nil, "банк не сдвигался")
end)

test("обе Bank вместе по умолчанию не меняют режим pan", function()
  local st = setup({ tracks = 12 })
  st.note_on(BL); st.run(0.06)
  st.note_on(BR); st.run(0.06)
  st.note_off(BL); st.run(0.06); st.note_off(BR); st.run(0.06)
  for i = 1, 8 do check(st.tracks[i].I_PANMODE == 0, "режим pan не тронут " .. i) end
  no_errors(st)
end)

test("удаление трека банка: следующий подтягивается", function()
  local st = setup({ tracks = 12 })
  local t1, t2 = st.tracks[1], st.tracks[2]
  st.remove_track(t1)
  st.run(0.3)
  press(st, MUTE[1])
  check(t2.B_MUTE == 1, "первая полоса теперь бывший 2-й")
  -- удаление в середине
  local t5 = st.tracks[5]
  st.remove_track(st.tracks[3])
  st.run(0.3)
  press(st, MUTE[4])
  check(t5.B_MUTE == 1, "полосы сдвинулись")
  no_errors(st)
end)

test("скрытые в миксере треки пропускаются", function()
  local st = setup({ tracks = 10, before = function(s) s.tracks[2].B_SHOWINMIXER = 0 end })
  press(st, MUTE[2])
  check(st.tracks[3].B_MUTE == 1, "вторая полоса = 3-й трек")
  check(st.tracks[2].B_MUTE == 0, "скрытый не тронут")
end)

test("посылы: страницы, подсветка номера, ручка", function()
  local st = setup({
    cfg = "return { send_all_note = 28, global_sends = true }",
    before = function(s)
      local bus1 = s.add_track("Reverb")
      local bus2 = s.add_track("Delay")
      s.add_send(s.tracks[1], bus1, 1); s.add_send(s.tracks[1], bus2, 1)
      s.add_send(s.tracks[2], bus1, 1)
      s.tracks[3].I_RECARM = 1
    end,
  })
  press(st, SENDALL)          -- страница 2
  check(st.led(REC[1]) == 127 and st.led(REC[2]) == 127, "диоды Rec 1-2 горят (страница 2)")
  check(st.led(REC[3]) == 0, "rec-диод 3 не горит, хотя трек взведён: показываем номер страницы")
  st.run(1.5)
  check(st.led(REC[3]) == 127, "после показа диоды вернулись к rec-состоянию")
  check(st.led(REC[1]) == 0, "rec-диод 1 вернулся")
  -- ручка верхнего ряда: страница 2 -> второй посыл трека 1
  local zero = math.floor(step_for_gain(1))
  st.cc(TOP[1], zero); st.run(0.1)
  st.cc(TOP[1], zero - 20); st.run(0.1)
  check(st.tracks[1].sends[2].D_VOL < 1, "второй посыл изменён")
  check(st.tracks[1].sends[1].D_VOL == 1, "первый не тронут")
  -- у трека 2 нет второго посыла
  st.cc(TOP[2], zero); st.run(0.1); st.cc(TOP[2], 10); st.run(0.1)
  check(st.tracks[2].sends[1].D_VOL == 1, "у трека без этого посыла ручка молчит")
  press(st, SENDALL)          -- страницы по кругу: 2 -> 1
  st.cc(TOP[2], zero); st.run(0.1); st.cc(TOP[2], zero - 30); st.run(0.1)
  check(st.tracks[2].sends[1].D_VOL < 1, "на странице 1 трек 2 управляется")
  no_errors(st)
end)

test("посылы по имени получателя", function()
  local st = setup({
    cfg = "return { send_all_note = 28, sends_by_name = true, global_sends = true }",
    before = function(s)
      local bus1 = s.add_track("Reverb")
      local bus2 = s.add_track("Delay")
      s.add_send(s.tracks[1], bus1, 1)               -- Reverb
      s.add_send(s.tracks[2], bus2, 1); s.add_send(s.tracks[2], bus1, 1) -- Delay, Reverb
    end,
  })
  local zero = math.floor(step_for_gain(1))
  -- страница 1 = Reverb: у трека 2 это второй посыл
  st.cc(TOP[2], zero); st.run(0.1); st.cc(TOP[2], zero - 25); st.run(0.1)
  check(st.tracks[2].sends[2].D_VOL < 1 and st.tracks[2].sends[1].D_VOL == 1, "Reverb трека 2 — его второй посыл")
  no_errors(st)
end)

test("Send All удержание: выкл/вкл, блокировка", function()
  local st = setup({ cfg = "return { send_all_note = 28 }", tracks = 12 })
  st.note_on(SENDALL); st.run(1.3); st.note_off(SENDALL); st.run(0.1)
  check(st.led(BL) == 127 and st.led(BR) == 127, "пауза: оба bank-диода горят")
  check(st.toggles[1234] == 0, "кнопка панели выключена")
  check(st.tracks[1].I_SPACER == 0 and st.tracks[9].I_SPACER == 0, "пробелы убраны")
  press(st, MUTE[1])
  check(st.tracks[1].B_MUTE == 0, "кнопки заблокированы")
  st.cc(FADER[1], 10); st.cc(FADER[1], 120); st.run(0.1)
  check(near(st.tracks[1].D_VOL, 1), "фейдер заблокирован")
  press(st, BR)
  check(st.mixer_scroll == nil, "банк не листается")
  st.note_on(SENDALL); st.run(1.3); st.note_off(SENDALL); st.run(0.1)
  check(st.led(BL) == 0 and st.led(BR) == 0, "включились: bank-диоды снова тёмные")
  check(st.toggles[1234] == 1, "кнопка панели включена")
  check(st.tracks[1].I_SPACER == 1, "пробелы вернулись")
  press(st, MUTE[1])
  check(st.tracks[1].B_MUTE == 1, "кнопки снова работают")
  -- подхват сбросился: фейдер должен снова «дойти» до значения
  local zero = math.floor(step_for_gain(1))
  st.cc(FADER[2], 5); st.run(0.1)
  check(near(st.tracks[2].D_VOL, 1), "после включения нужен подхват")
  no_errors(st)
end)

test("Solo + Send All: снять все соло", function()
  local st = setup({ cfg = "return { send_all_note = 28 }" })
  press(st, SOLO)
  check(st.tracks[1].I_SOLO == 2, "соло банка")
  st.tracks[10].I_SOLO = 2
  st.note_on(SOLO); st.run(0.06)
  press(st, SENDALL)
  st.note_off(SOLO); st.run(0.06)
  local any = false
  for _, t in ipairs(st.tracks) do if t.I_SOLO ~= 0 then any = true end end
  check(not any, "все соло сняты")
  check(st.tracks[1].I_SOLO == 0, "и соло банка после отпускания Solo не вернулось")
end)

test("запасной путь: Send All как дамп CC", function()
  local st = setup({ cfg = "return { global_sends = true }" })
  local function dump()
    for i = 1, 8 do st.cc(FADER[i], 50); st.cc(TOP[i], 30); st.cc(MID[i], 30) end
    st.cc(62, 100)
  end
  dump(); st.run(0.1)
  check(st.tracks[1].D_VOL == 1, "дамп не двигает треки")
  st.run(0.7)
  check(st.led(REC[1]) == 127, "одно нажатие: страница сменилась (но у нас одна страница — показ номера)")
  st.run(1.5)
  -- двойное нажатие = вкл/выкл
  dump(); st.run(0.2); dump(); st.run(0.2)
  check(st.led(BL) == 127 and st.led(BR) == 127, "двойное нажатие выключило (пауза)")
  no_errors(st)
end)

test("канал и устройство фильтруются", function()
  local st = setup()
  st.note_on(MUTE[1], 1); st.run(0.1)
  check(st.tracks[1].B_MUTE == 0, "другой MIDI-канал игнорируется")
  st.push(0x90, MUTE[1], 127, 0); st.run(0.1)
  check(st.tracks[1].B_MUTE == 0, "другое устройство игнорируется")
  no_errors(st)
end)

test("выход: пробелы сняты, диоды погашены", function()
  local st = setup({ tracks = 12 })
  press(st, MUTE[1])
  check(st.led(MUTE[1]) == 127, "диод горел")
  st.exit()
  check(st.tracks[1].I_SPACER == 0 and st.tracks[9].I_SPACER == 0, "пробелы убраны")
  check(st.led(MUTE[1]) == 0 and st.led(BL) == 0, "диоды погашены")
  check(st.toggles[1234] == 0, "кнопка панели выключена")
end)

test("после сбоя старые пробелы убираются при старте", function()
  local st = setup({
    tracks = 12,
    before = function(s)
      s.tracks[5].I_SPACER = 1
      s.ext["MidiMixLua/spacers"] = s.tracks[5].guid
    end,
  })
  check(st.tracks[5].I_SPACER == 0, "старый пробел убран")
  check(st.tracks[1].I_SPACER == 1, "новый поставлен")
end)

test("пробел, который поставил сам пользователь, не трогаем", function()
  local st = setup({ tracks = 12, before = function(s) s.tracks[9].I_SPACER = 1 end })
  press(st, BR)
  press(st, BL)
  st.exit()
  check(st.tracks[9].I_SPACER == 1, "пробел пользователя остался")
end)

test("если I_SPACER не работает — выключаем пробелы и говорим", function()
  local st = setup({ spacer_works = false })
  local said = false
  for _, l in ipairs(st.console) do if l:find("I_SPACER") then said = true end end
  check(said, "сообщение в консоли")
  no_errors(st)
end)

test("окно ReaImGui рисуется без ошибок", function()
  local st = setup({ gui = true, tracks = 3 })
  st.run(0.5)
  check(st.gui_calls > 20, "вызовы ReaImGui были")
  no_errors(st)
end)

test("без ReaImGui всё работает", function()
  local st = setup({ gui = false })
  press(st, MUTE[1])
  check(st.tracks[1].B_MUTE == 1, "работает без окна")
  no_errors(st)
end)

test("файл настроек midimix_config.lua", function()
  local st = setup({ cfg = "return { bank_size = 4, spacers = false, map = { mute = {2,5,8,11,14,17,20,23} } }" })
  press(st, 2)
  check(st.tracks[1].B_MUTE == 1, "новая нота mute")
  press(st, MUTE[1])
  check(st.tracks[1].B_MUTE == 1, "старая нота не работает (не должна менять)")
  press(st, 11)
  check(st.tracks[4].B_MUTE == 1, "полоса 4")
  press(st, 14)
  check(st.tracks[5].B_MUTE == 0, "полоса 5 вне банка из 4")
  check(st.tracks[1].I_SPACER == 0, "пробелы выключены")
  press(st, BR)
  check(st.mixer_scroll == st.tracks[5], "банк из 4 листается на 4")
  no_errors(st)
end)

test("мастер-фейдер", function()
  local st = setup()
  local zero = math.floor(step_for_gain(1))
  st.cc(62, zero); st.run(0.1)
  st.cc(62, zero - 30); st.run(0.1)
  check(st.R.GetMasterTrack().D_VOL < 1, "мастер управляется")
end)


test("bank-диод: мигает тем чаще, чем дальше банк", function()
  local st = setup({ tracks = 30 })
  local function toggles(secs)
    local from = #st.out
    st.run(secs)
    local n = 0
    for i = from + 1, #st.out do if st.out[i][2] == BR then n = n + 1 end end
    return n
  end
  check(toggles(2) == 0, "первый банк: диод не мигает")
  press(st, BR)
  local a = toggles(2)
  press(st, BR)
  local b = toggles(2)
  check(a >= 3, "второй банк: диод мигает")
  check(b > a, "третий банк мигает чаще")
  press(st, BL); press(st, BL)
  check(toggles(1) == 0, "вернулись на первый банк: не мигает")
  no_errors(st)
end)

test("старт: диоды идут по кругу mute 1..8, rec 8..1", function()
  local st = setup({ before = function() end })
  -- setup уже прокрутил анимацию; ищем первые включения в журнале
  local order = {}
  for _, m in ipairs(st.out) do
    if m[3] == 127 and #order < 16 then order[#order + 1] = m[2] end
  end
  local want = {}
  for i = 1, 8 do want[#want + 1] = MUTE[i] end
  for i = 8, 1, -1 do want[#want + 1] = REC[i] end
  for i = 1, 16 do check(order[i] == want[i], "шаг круга " .. i) end
end)

test("выход: mute и rec дважды мигают", function()
  local st = setup()
  local from = #st.out
  st.exit()
  local ons = 0
  for i = from + 1, #st.out do
    if st.out[i][3] == 127 and st.out[i][2] == MUTE[1] then ons = ons + 1 end
  end
  check(ons == 2, "mute 1 зажёгся дважды")
  check(st.led(MUTE[1]) == 0 and st.led(REC[8]) == 0 and st.led(BL) == 0, "в конце всё погашено")
end)

test("Send All при зажатом Rec N: посыл только этого трека", function()
  local st = setup({
    cfg = "return { send_all_note = 28, track_sends = true }",
    before = function(s)
      local bus1 = s.add_track("Reverb")
      local bus2 = s.add_track("Delay")
      s.add_send(s.tracks[1], bus1, 1); s.add_send(s.tracks[1], bus2, 1)
      s.add_send(s.tracks[2], bus1, 1); s.add_send(s.tracks[2], bus2, 1)
    end,
  })
  local zero = math.floor(step_for_gain(1))
  st.note_on(REC[2]); st.run(0.06)
  press(st, SENDALL)
  st.note_off(REC[2]); st.run(0.06)
  check(st.tracks[2].I_RECARM == 0, "rec не переключился: Rec служил модификатором")
  st.cc(TOP[2], zero); st.run(0.1); st.cc(TOP[2], zero - 30); st.run(0.1)
  check(st.tracks[2].sends[2].D_VOL < 1, "у трека 2 управляется второй посыл")
  check(st.tracks[2].sends[1].D_VOL == 1, "первый посыл трека 2 не тронут")
  st.cc(TOP[1], zero); st.run(0.1); st.cc(TOP[1], zero - 30); st.run(0.1)
  check(st.tracks[1].sends[1].D_VOL < 1, "у трека 1 остался первый посыл")
  check(st.tracks[1].sends[2].D_VOL == 1, "второй посыл трека 1 не тронут")
  press(st, REC[3])
  check(st.tracks[3].I_RECARM == 1, "обычное нажатие Rec по-прежнему взводит трек")
  press(st, SENDALL)  -- общий переход страницы сбрасывает выбор по трекам
  no_errors(st)
end)


test("окно: кнопки Pause/Resume и Close script, N/N посыла", function()
  local st = setup({
    gui = true,
    before = function(s)
      local bus1 = s.add_track("Reverb")
      local bus2 = s.add_track("Делей")
      s.add_send(s.tracks[1], bus1, 1); s.add_send(s.tracks[1], bus2, 1)
      s.add_send(s.tracks[2], bus1, 1)
    end,
  })
  st.run(0.3)
  no_errors(st)
  st.gui_click = "Pause"; st.run(0.1); st.gui_click = nil; st.run(0.1)
  check(st.led(BL) == 127 and st.led(BR) == 127, "кнопка Pause поставила контроллер на паузу")
  st.gui_click = "Resume"; st.run(0.1); st.gui_click = nil; st.run(0.1)
  check(st.led(BL) == 0, "кнопка Resume вернула работу")
  no_errors(st)
  st.gui_click = "Close script"; st.run(0.3); st.gui_click = nil
  local n = st.gui_calls
  st.run(0.3)
  check(st.gui_calls == n, "после Close script цикл остановлен")
end)

test("Rec: при track_sends=false переключается сразу, при true на отпускании", function()
  local st = setup({ cfg = "return { track_sends = false }" })
  st.note_on(REC[1]); st.run(0.1)
  check(st.tracks[1].I_RECARM == 1, "rec взведён, кнопка ещё держится")
  st.note_off(REC[1]); st.run(0.06)
  check(st.tracks[1].I_RECARM == 1, "и при отпускании не переключается обратно")
  local st2 = setup()
  st2.note_on(REC[1]); st2.run(0.1)
  check(st2.tracks[1].I_RECARM == 0, "по умолчанию пока держим — ещё нет")
  st2.note_off(REC[1]); st2.run(0.06)
  check(st2.tracks[1].I_RECARM == 1, "по умолчанию переключился при отпускании")
end)


test("обычный Send All по умолчанию ничего не переключает", function()
  local st = setup({
    cfg = "return { send_all_note = 28 }",
    before = function(s)
      local bus1 = s.add_track("Reverb")
      local bus2 = s.add_track("Delay")
      s.add_send(s.tracks[1], bus1, 1); s.add_send(s.tracks[1], bus2, 1)
    end,
  })
  local zero = math.floor(step_for_gain(1))
  press(st, SENDALL); st.run(0.8)      -- тап = режим «инструмент»
  press(st, SENDALL); st.run(0.8)      -- и обратно в микшер
  st.cc(TOP[1], zero); st.run(0.1); st.cc(TOP[1], zero - 30); st.run(0.1)
  check(st.tracks[1].sends[1].D_VOL < 1, "ручка по-прежнему на первом посыле")
  check(st.tracks[1].sends[2].D_VOL == 1, "второй посыл не тронут")
  no_errors(st)
end)


test("диоды соло: ноты 2,5,8... отражают соло, mute-диод не трогаем при удержании Solo", function()
  local st = setup()
  local SOLO_LED = { 2, 5, 8, 11, 14, 17, 20, 23 }
  check(st.led(SOLO_LED[1]) == 0, "соло-диод 1 погашен на старте")
  st.note_on(SOLO); st.run(0.06)
  press(st, SOLO_LED[2])               -- Solo + Mute 2: устройство шлёт ноту 5
  st.note_off(SOLO); st.run(0.1)
  check(st.tracks[2].I_SOLO ~= 0, "соло второго трека включено")
  check(st.led(SOLO_LED[2]) == 127, "соло-диод 2 горит")
  check(st.led(SOLO_LED[1]) == 0, "соло-диод 1 по-прежнему тёмный")
  -- пока Solo зажат, mute-диод трека 1 не должен выдавать соло-состояние
  st.note_on(SOLO); st.run(0.1)
  check(st.led(MUTE[1]) == 0, "mute-диод 1 остался тёмным (mute не включён)")
  st.note_off(SOLO); st.run(0.1)
  press(st, SOLO_LED[2])               -- (Solo не зажат) нота 5 всё равно = соло трека 2
  no_errors(st)
end)

test("настройки: сохранение в ExtState, живое применение, сброс, restart-параметры", function()
  local st = setup({ gui = true, spacer_works = true })
  local function count_spacers()
    local n = 0
    for _, t in ipairs(st.tracks) do if t.I_SPACER == 1 then n = n + 1 end end
    return n
  end
  check(count_spacers() == 2, "пробелы включены по умолчанию")
  st.gui_set = { ["Show the bank with##highlight"] = 3, ["Pickup tolerance##pickup_window"] = 9,
                 ["Tracks in a bank##bank_size"] = 4 }
  st.run(0.3); st.gui_set = nil; st.run(0.3)
  check(st.ext["MidiMixLua_settings/highlight"] == "none", "highlight сохранён")
  check(st.ext["MidiMixLua_settings/pickup_window"] == "9", "pickup_window сохранён")
  check(st.ext["MidiMixLua_settings/bank_size"] == "4", "bank_size сохранён")
  check(count_spacers() == 0, "пробелы убраны сразу (живая настройка)")
  no_errors(st)
  -- настройки восстанавливаются при новом запуске и главнее config.lua
  local saved = {}
  for k, v in pairs(st.ext) do if k:find("^MidiMixLua_settings/") then saved[k] = v end end
  local st2 = setup({ gui = true, spacer_works = true, cfg = "return { highlight = \"spacers\" }",
    before = function(s) for k, v in pairs(saved) do s.ext[k] = v end end })
  local n2 = 0
  for _, t in ipairs(st2.tracks) do if t.I_SPACER == 1 then n2 = n2 + 1 end end
  check(n2 == 0, "сохранённое значение главнее midimix_config.lua")
  -- сброс
  st2.gui_click = "Reset to defaults"; st2.run(0.2); st2.gui_click = nil; st2.run(0.2)
  check(st2.ext["MidiMixLua_settings/highlight"] == "", "сброс очистил сохранённое")
  local n3 = 0
  for _, t in ipairs(st2.tracks) do if t.I_SPACER == 1 then n3 = n3 + 1 end end
  check(n3 == 2, "после сброса пробелы вернулись (значение из config.lua)")
  no_errors(st2)
end)

test("удержание Bank: прыжок в первый / последний банк", function()
  local st = setup({ tracks = 20 })
  local function first_track_vol_target() return st.mixer_scroll and st.mixer_scroll.name end
  st.note_on(BR); st.run(0.7); st.note_off(BR); st.run(0.2)
  check(st.mixer_scroll and st.mixer_scroll.name == "T17", "удержание Bank Right: последний банк (T17)")
  st.note_on(BR); st.run(0.1); st.note_off(BR); st.run(0.2)
  check(st.mixer_scroll.name == "T17", "короткое нажатие за последним банком ничего не делает")
  st.note_on(BL); st.run(0.7); st.note_off(BL); st.run(0.2)
  check(st.mixer_scroll.name == "T1", "удержание Bank Left: первый банк (T1)")
  st.note_on(BR); st.run(0.1); st.note_off(BR); st.run(0.2)
  check(st.mixer_scroll.name == "T9", "короткое нажатие листает на один банк")
  no_errors(st)
end)

test("separator: не управляется; типы дорожек", function()
  local st = setup({ gui = true, tracks = 12, before = function(s)
    s.tracks[3].name = "--- Drums ---"             -- пустой, имя-разделитель
    s.tracks[5].name = "--- Synths"; s.tracks[5].items = 1   -- не пустой: не separator
    s.tracks[6].instrument = true
    s.tracks[7].I_FOLDERDEPTH = 1
    s.tracks[8].recvs = { {} }
    s.tracks[2].vca = true
  end })
  local v0 = st.tracks[3].D_VOL
  for _, v in ipairs({ 5, 20, 100, 40, 0 }) do st.cc(FADER[3], v); st.cc(FADER[4], v); st.run(0.1) end
  check(st.tracks[3].D_VOL == v0, "фейдер на separator ничего не меняет")
  check(st.tracks[4].D_VOL ~= v0, "соседний фейдер работает")
  st.note_on(7); st.run(0.05); st.note_off(7); st.run(0.1)   -- Mute 3
  check((st.tracks[3].B_MUTE or 0) == 0, "Mute на separator не работает")
  st.note_on(9); st.run(0.05); st.note_off(9); st.run(0.1)   -- Rec 3
  check((st.tracks[3].I_RECARM or 0) == 0, "Rec на separator не работает")
  st.note_on(SOLO); st.run(0.05); st.note_off(SOLO); st.run(0.1)  -- соло банка
  check((st.tracks[3].I_SOLO or 0) == 0, "соло банка не трогает separator")
  check((st.tracks[4].I_SOLO or 0) ~= 0, "соло банка трогает обычные дорожки")
  no_errors(st)
end)

test("separator: skip_separators пропускает его в банке", function()
  local st = setup({ tracks = 12, cfg = "return { skip_separators = true }", before = function(s)
    s.tracks[3].name = "---"
  end })
  local v0 = st.tracks[3].D_VOL
  for _, v in ipairs({ 5, 20, 100, 40, 0 }) do st.cc(FADER[3], v); st.run(0.1) end
  check(st.tracks[4].D_VOL == 0, "третий фейдер управляет T4 (separator пропущен)")
  check(st.tracks[3].D_VOL == v0, "T3 не тронут")
  no_errors(st)
end)

test("модули не засоряют глобальное окружение", function()
  local st = setup({ tracks = 3 })
  check(rawget(_G, "CFG") == nil and rawget(_G, "S") == nil, "CFG и S не в _G")
  no_errors(st)
end)

test("окно: полоса в стиле MPC (метры, выбранный трек, посыл)", function()
  local st = setup({ gui = true, tracks = 4 })
  st.peak = { [st.tracks[1].name] = 0.5, [st.tracks[2].name] = 1.4 }
  st.tracks[1].I_SELECTED = 1
  st.run(0.6)
  no_errors(st)
  check(not st.console_has_window_error, "полосы рисуются")
  st.peak = nil; st.run(2.5)
  no_errors(st)
  -- индикатор считается после фейдера: тише фейдер -> ниже уровень
  st.peak = { [st.tracks[1].name] = 0.8 }
  st.tracks[1].D_VOL = 0.5; st.run(0.6)
  no_errors(st)
end)

test("окно: мастер-полоса, шкала до fader_max_db, метры следуют за панорамой", function()
  local function texts_have(st, str)
    for _, t in ipairs(st.gui_texts or {}) do if t == str then return true end end
    return false
  end
  local st = setup({ gui = true, tracks = 4 })
  st.run(0.4)
  no_errors(st)
  check(texts_have(st, "MASTER"), "в окне есть полоса мастера")
  check(texts_have(st, "+12"), "по умолчанию шкала доходит до +12")
  local st6 = setup({ gui = true, tracks = 4, cfg = "return { fader_max_db = 6 }" })
  st6.run(0.4)
  no_errors(st6)
  check(texts_have(st6, "+6") and not texts_have(st6, "+12"), "при fader_max_db = 6 шкала до +6")
  -- метры: ширина 15 = один канал; при панораме вправо левый канал пропадает
  local function meter_rects(s)
    local n = 0
    for _, r in ipairs(s.gui_rects or {}) do if r.x2 - r.x1 == 15 then n = n + 1 end end
    return n
  end
  local function count_with_pan(pan)
    local s2 = setup({ gui = true, tracks = 4 })
    s2.peak = { [s2.tracks[1].name] = 0.5 }
    s2.tracks[1].D_PAN = pan
    s2.run(0.5)
    return meter_rects(s2)
  end
  local center, right = count_with_pan(0), count_with_pan(1)
  check(center > 0 and right > 0 and right < center, "панорама вправо гасит левый метр (" .. center .. " -> " .. right .. ")")
  no_errors(st)
end)

test("окно: заголовок цвета Akai Red, стили снимаются, группы настроек сворачиваются", function()
  local st = setup({ gui = true, tracks = 4 })
  st.run(0.5)
  no_errors(st)
  local red = false
  for _, c in ipairs(st.gui_push or {}) do if c == 0xBC012EFF then red = true end end
  check(red, "заголовок активного окна красный (Akai Red)")
  check(#(st.gui_push or {}) > 0 and #(st.gui_push or {}) == (st.gui_pop or 0), "стили заголовка снимаются (" .. #(st.gui_push or {}) .. "/" .. tostring(st.gui_pop) .. ")")
end)

test("мастер: Bank Right + Mute / Solo / нижняя ручка", function()
  local st = setup({ tracks = 12 })
  local m = _G.reaper.GetMasterTrack(0)
  st.note_on(BR); st.run(0.06)
  st.note_on(MUTE[3]); st.run(0.06); st.note_off(MUTE[3]); st.run(0.06)
  check(m.B_MUTE == 1, "Bank Right + Mute: мастер заглушён")
  check((st.tracks[3].B_MUTE or 0) == 0, "дорожка 3 не тронута")
  st.note_on(SOLO); st.run(0.06); st.note_off(SOLO); st.run(0.06)
  check(m.I_SOLO and m.I_SOLO ~= 0, "Bank Right + Solo: мастер в соло")
  check((st.tracks[1].I_SOLO or 0) == 0, "соло банка не сработало")
  st.cc(BOT[2], 64); st.run(0.1); st.cc(BOT[2], 127); st.run(0.1)
  check(near(m.D_PAN or 0, 1, 0.01), "нижняя ручка двигает pan мастера")
  check(near(st.tracks[2].D_PAN or 0, 0), "pan дорожки 2 не двигался")
  st.note_off(BR); st.run(0.2)
  check(st.mixer_scroll == nil, "после мастер-слоя Bank Right не листает банк")
  st.note_on(MUTE[3]); st.run(0.06); st.note_off(MUTE[3]); st.run(0.06)
  check(st.tracks[3].B_MUTE == 1, "без Bank Right Mute снова трогает дорожку")
  check(m.B_MUTE == 1, "а мастер не изменился")
  -- после слоя обычный pan требует нового подхвата, дорожка не прыгает
  local p0 = st.tracks[2].D_PAN or 0
  st.cc(BOT[2], 127); st.run(0.1)
  check(near(st.tracks[2].D_PAN or 0, p0, 0.01), "pan дорожки не прыгнул после мастер-слоя")
  -- на паузе слой выключен
  no_errors(st)
end)

test("двойное нажатие Solo возвращает соло банка как было", function()
  local st = setup({ tracks = 12 })
  st.tracks[2].I_SOLO = 2                      -- одна дорожка уже в соло
  st.note_on(SOLO); st.run(0.05); st.note_off(SOLO); st.run(0.1)
  check(st.tracks[1].I_SOLO ~= 0 and st.tracks[5].I_SOLO ~= 0, "первое нажатие включило соло банка")
  st.note_on(SOLO); st.run(0.05); st.note_off(SOLO); st.run(0.2)
  check(st.tracks[2].I_SOLO == 2, "соло трека 2 вернулось")
  for i = 1, 8 do if i ~= 2 then check((st.tracks[i].I_SOLO or 0) == 0, "соло трека " .. i .. " выключено") end end
  no_errors(st)
end)

test("настройки: свёрнутая группа показывает «restart needed»", function()
  local st = setup({ gui = true, tracks = 4 })
  st.gui_set = { ["Tracks in a bank##bank_size"] = 4 }
  st.run(0.4)
  st.gui_header_titles = {}
  st.run(0.4)
  local found = false
  for _, t in ipairs(st.gui_header_titles) do if tostring(t):find("restart needed", 1, true) then found = true end end
  check(found, "заголовок группы помечен, даже если группа свёрнута")
  no_errors(st)
end)

test("тип дорожки: вручную по клику, separator по высоте, VCA в старших группах", function()
  local st = setup({ gui = true, tracks = 12, before = function(s)
    s.tracks[2].I_HEIGHTOVERRIDE = 23        -- пустая, высота задана вручную минимальной: separator
    s.tracks[3].I_TCPH = 90                  -- пустая обычная: audio
  end })
  -- клик по подписи типа у полосы 3 (T3): auto -> audio (вручную)
  local function ptype(n) return st.tracks[n].strs and st.tracks[n].strs["P_EXT:midimix_type"] end
  check(ptype(3) == nil, "сначала тип автоматический")
  for _, want in ipairs({ "audio", "instrument", "bus", "vca", "folder", "separator" }) do
    st.gui_click = "type3"; st.run(0.03); st.gui_click = nil; st.run(0.15)
    check(ptype(3) == want, "после клика тип = " .. want .. " (получено " .. tostring(ptype(3)) .. ")")
  end
  st.gui_click = "type3"; st.run(0.03); st.gui_click = nil; st.run(0.15)
  check(ptype(3) == "" or ptype(3) == nil, "после последнего типа снова автоматический")
  -- T3 вручную separator: не управляется
  st.tracks[3].strs["P_EXT:midimix_type"] = "separator"; st.run(1.2)
  local v0 = st.tracks[3].D_VOL
  for _, v in ipairs({ 5, 20, 100, 40, 0 }) do st.cc(FADER[3], v); st.run(0.1) end
  check(st.tracks[3].D_VOL == v0, "вручную заданный separator не управляется")
  -- T2: separator по высоте
  for _, v in ipairs({ 5, 20, 100, 40, 0 }) do st.cc(FADER[2], v); st.run(0.1) end
  check(st.tracks[2].D_VOL == 1, "пустой маленький трек считается separator")
  no_errors(st)
end)

test("свёрнутый трек в папке не separator (I_TCPH мал, но высота не задана)", function()
  local st = setup({ tracks = 6, before = function(s) s.tracks[2].I_TCPH = 23 end })
  for _, v in ipairs({ 5, 20, 100, 40, 0 }) do st.cc(FADER[2], v); st.run(0.1) end
  check(st.tracks[2].D_VOL == 0, "маленький пустой трек управляется")
  no_errors(st)
end)

test("банк следует за прокруткой микшера (follow_mixer)", function()
  local st = setup({ tracks = 20, cfg = "return { follow_mixer = true }" })
  st.mixer_scroll = st.tracks[9]; st.run(0.8)   -- пользователь прокрутил микшер
  for _, v in ipairs({ 5, 20, 100, 40, 0 }) do st.cc(FADER[1], v); st.run(0.1) end
  check(st.tracks[9].D_VOL == 0, "первый фейдер теперь управляет T9")
  check(st.mixer_scroll.name == "T9", "микшер не отброшен назад")
  no_errors(st)
end)

test("без follow_mixer банк не двигается от прокрутки", function()
  local st = setup({ tracks = 20 })
  st.mixer_scroll = st.tracks[9]; st.run(0.8)
  for _, v in ipairs({ 5, 20, 100, 40, 0 }) do st.cc(FADER[1], v); st.run(0.1) end
  check(st.tracks[1].D_VOL == 0, "фейдер 1 по-прежнему T1")
end)

test("режимы Rec: двойное нажатие Solo переключает arm -> send -> fx", function()
  local st = setup({ tracks = 4, before = function(s)
    local bus = s.add_track("Bus")
    s.add_send(s.tracks[1], bus, 1)
    for i = 1, 5 do s.tracks[i].I_FXEN = 1 end
  end })
  local function dtap() press(st, SOLO); st.run(0.1); press(st, SOLO); st.run(0.2) end
  press(st, REC[1]); st.run(0.1)
  check(st.tracks[1].I_RECARM == 1, "режим arm: Rec взводит запись")
  press(st, REC[1]); st.run(0.1)
  dtap()
  for i = 1, 4 do check((st.tracks[i].I_SOLO or 0) == 0, "двойное нажатие Solo не оставляет соло у T" .. i) end
  check(st.led(REC[1]) == 127 and st.led(REC[2]) == 127 and st.led(REC[3]) == 0, "две Rec-лампы показывают режим 2")
  st.run(1.5)
  press(st, REC[1]); st.run(0.1)
  check(st.tracks[1].sends[1].B_MUTE == 1, "режим send: Rec глушит посыл")
  check(st.led(REC[1]) == 127, "диод горит: посыл заглушён")
  check((st.tracks[1].I_RECARM or 0) == 0, "запись не взведена")
  press(st, REC[1]); st.run(0.1)
  check(st.tracks[1].sends[1].B_MUTE == 0, "ещё раз: посыл включён")
  dtap(); st.run(1.5)
  press(st, REC[2]); st.run(0.1)
  check(st.tracks[2].I_FXEN == 0, "режим fx: Rec обходит цепочку FX")
  check(st.led(REC[2]) == 127, "диод горит: FX в bypass")
  dtap(); st.run(1.5)
  press(st, REC[3]); st.run(0.1)
  check(st.tracks[3].I_RECARM == 1, "после третьего двойного нажатия снова arm")
  no_errors(st)
end)

test("режим Rec переключается из окна", function()
  local st = setup({ gui = true, tracks = 4, before = function(s)
    for i = 1, 4 do s.tracks[i].I_FXEN = 1 end
  end })
  st.gui_click = "FX bypass##recmode3"; st.run(0.03); st.gui_click = nil; st.run(0.2)
  check(st.led(REC[1]) == 127 and st.led(REC[3]) == 127 and st.led(REC[4]) == 0, "три Rec-лампы: режим FX bypass")
  st.run(1.5)
  press(st, REC[1]); st.run(0.1)
  check(st.tracks[1].I_FXEN == 0, "Rec обходит FX после выбора режима в окне")
  st.gui_click = "Rec arm##recmode1"; st.run(0.03); st.gui_click = nil; st.run(1.5)
  press(st, REC[2]); st.run(0.1)
  check(st.tracks[2].I_RECARM == 1, "обратно в arm из окна")
  no_errors(st)
end)

test("два маркер-трека MidiMix: вокруг банка, едут за ним, не входят в банк, убираются", function()
  local st = setup({ tracks = 20, spacer_works = true, cfg = "return { highlight = 'markers' }" })
  local function marks()
    local r = {}
    for i, t in ipairs(st.tracks) do if t.name:find("^MidiMix") then r[#r + 1] = i end end
    return r
  end
  st.run(0.5)
  local mk = marks()
  check(#mk == 2 and mk[1] == 1 and mk[2] == 10, "маркеры: 1 перед T1 и 10 после T8")
  check(st.tracks[10 - 1].name == "T8" and st.tracks[2].name == "T1", "банк T1..T8 между маркерами")
  check(#st.tracks == 22, "добавлено ровно два трека")
  for _, v in ipairs({ 5, 20, 100, 40, 0 }) do st.cc(FADER[1], v); st.run(0.1) end
  check(st.tracks[2].D_VOL == 0 and st.tracks[1].D_VOL == 1, "первый фейдер управляет T1, а не маркером")
  press(st, BR); st.run(0.8)
  mk = marks()
  check(#mk == 2 and st.tracks[mk[1] + 1].name == "T9" and st.tracks[mk[2] - 1].name == "T16", "после Bank Right маркеры вокруг T9..T16")
  check(#st.tracks == 22, "маркеров по-прежнему два")
  local function dump()
    for i = 1, 8 do st.cc(FADER[i], 50); st.cc(TOP[i], 30); st.cc(MID[i], 30) end
    st.cc(62, 100)
  end
  dump(); st.run(0.2); dump(); st.run(0.8)   -- пауза
  check(#marks() == 0, "на паузе маркеры убраны")
  dump(); st.run(0.2); dump(); st.run(0.8)
  check(#marks() == 2, "после паузы маркеры вернулись")
  st.exit()
  check(#marks() == 0 and #st.tracks == 20, "при выходе маркеры убраны")
  no_errors(st)
end)

test("маркеры: нижний стоит после папки, если последний трек банка - папка", function()
  local st = setup({ tracks = 12, cfg = "return { highlight = 'markers', bank_size = 2 }", before = function(s)
    s.tracks[2].I_FOLDERDEPTH = 1; s.tracks[4].I_FOLDERDEPTH = -1   -- папка T2 (T3, T4)
  end })
  st.run(0.5)
  local names = {}
  for _, t in ipairs(st.tracks) do names[#names + 1] = t.name:sub(1, 7) end
  local s = table.concat(names, ",")
  check(s:find("^MidiMix,T1,T2,T3,T4,MidiMix"), "банк T1,T2: нижний маркер после папки (" .. s .. ")")
  press(st, 25); st.run(0.1)
  no_errors(st)
end)

test("режим color: треки банка подкрашены, цвета возвращаются", function()
  local st = setup({ tracks = 20, cfg = "return { highlight = 'color' }", before = function(s)
    s.tracks[1].I_CUSTOMCOLOR = 0x1000000 | (200) | (100 << 8) | (50 << 16)
  end })
  st.run(0.4)
  local c1 = st.tracks[1].I_CUSTOMCOLOR
  check(c1 ~= (0x1000000 | 200 | (100 << 8) | (50 << 16)) and c1 & 0x1000000 ~= 0, "T1 подкрашен")
  check(st.tracks[2].I_CUSTOMCOLOR ~= 0, "T2 (без своего цвета) тоже подкрашен")
  check((st.tracks[9].I_CUSTOMCOLOR or 0) == 0, "T9 вне банка не тронут")
  press(st, BR); st.run(0.5)
  check(st.tracks[1].I_CUSTOMCOLOR == (0x1000000 | 200 | (100 << 8) | (50 << 16)), "T1 вернул исходный цвет после смены банка")
  check((st.tracks[2].I_CUSTOMCOLOR or 0) == 0, "T2 снова без цвета")
  check(st.tracks[9].I_CUSTOMCOLOR ~= 0, "T9 теперь подкрашен")
  st.exit()
  check((st.tracks[9].I_CUSTOMCOLOR or 0) == 0, "после выхода цвета на месте")
  no_errors(st)
end)

test("режим color: остатки прошлого запуска возвращают цвет при старте", function()
  local st = setup({ tracks = 4, cfg = "return { highlight = 'none' }", before = function(s)
    s.tracks[1].I_CUSTOMCOLOR = 0x1000000 | 255
    s.tracks[1].strs = { ["P_EXT:midimix_origcolor"] = tostring(0x1000000 | 50) }
  end })
  check(st.tracks[1].I_CUSTOMCOLOR == (0x1000000 | 50), "исходный цвет восстановлен")
end)

test("остатки прошлого запуска (помеченные маркер и пробел) чистятся при старте", function()
  local st = setup({ tracks = 6, spacer_works = true, before = function(s)
    local m = s.add_track("MidiMix \u{25BC}"); m.strs = { ["P_EXT:midimix_marker"] = "1" }
    s.tracks[2].I_SPACER = 1; s.tracks[2].strs = { ["P_EXT:midimix_spacer"] = "1" }
    s.tracks[3].I_SPACER = 1   -- чужой пробел, не трогаем
  end })
  local names = {}
  for _, t in ipairs(st.tracks) do names[#names + 1] = t.name end
  check(not table.concat(names, ","):find("MidiMix"), "старый маркер удалён")
  check(st.tracks[3].I_SPACER == 1, "чужой пробел остался")
  st.exit()
  check(st.tracks[3].I_SPACER == 1, "и после выхода чужой пробел остался")
  for i, t in ipairs(st.tracks) do if i ~= 3 then check(t.I_SPACER == 0, "после выхода наших пробелов нет (T" .. i .. ")") end end
end)

test("тип по layout трека; маркер берёт layout чужого separator", function()
  local st = setup({ tracks = 12, spacer_works = true, cfg = "return { highlight = 'markers' }", before = function(s)
    s.tracks[2].strs = { P_TCP_LAYOUT = "Separator", P_MCP_LAYOUT = "Separator" }
    s.tracks[2].items = 1                         -- не пустой: по имени/высоте не separator
    s.tracks[4].strs = { P_MCP_LAYOUT = "Bus mini" }
  end })
  st.run(0.5)
  for _, v in ipairs({ 5, 20, 100, 40, 0 }) do st.cc(FADER[2], v); st.cc(FADER[4], v); st.run(0.1) end
  local sep, bus
  for _, t in ipairs(st.tracks) do
    if t.name == "T2" then sep = t elseif t.name == "T4" then bus = t end
  end
  check(sep.D_VOL == 1, "трек с layout Separator не управляется")
  check(bus.D_VOL ~= 1, "трек с layout Bus управляется (тип bus)")
  local mk
  for _, t in ipairs(st.tracks) do if t.name:find("^MidiMix") then mk = t end end
  check(mk and mk.strs.P_TCP_LAYOUT == "Separator" and mk.strs.P_MCP_LAYOUT == "Separator", "маркер получил layout Separator")
  no_errors(st)
end)

test("окно: полоса с названием папки над треками внутри неё", function()
  local st = setup({ gui = true, tracks = 10, cfg = "return { bank_size = 2 }", before = function(s)
    s.tracks[2].name = "Drums"; s.tracks[2].I_FOLDERDEPTH = 1
    s.tracks[4].I_FOLDERDEPTH = -1                      -- Drums: T3, T4
  end })
  press(st, BR); st.run(0.3)                            -- банк T3, T4: сама папка Drums вне банка
  st.gui_texts = {}
  st.run(1.2)
  check(table.concat(st.gui_texts, "|"):find("Drums", 1, true), "название папки Drums показано над T3-T4")
  press(st, BL); st.run(0.3)                            -- банк T1, T2: внутри папки никого
  st.gui_texts = {}
  st.run(1.2)
  no_errors(st)
end)

test("режим инструмент: learn, ручка -> параметр плагина, Mute = окно, Rec = выбор, сброс, play/stop", function()
  local st = setup({ gui = true, tracks = 4, cfg = "return { send_all_note = 28 }", before = function(s)
    s.tracks[2].fxlist = { { guid = "{FX1}", name = "Dexed", params = { { name = "Cutoff", val = 0.2 }, { name = "Res", val = 0.5 } } } }
  end })
  press(st, SENDALL); st.run(0.9)                              -- режим инструмент
  check(st.led(MUTE[1]) == 0, "в режиме инструмент Mute-диоды без привязок тёмные")
  -- learn: включаем Learn mode в окне, крутим ручку 1 (верхний ряд), трогаем параметр Res у T2
  st.gui_set = { ["Learn mode (turn a knob, then touch a parameter)##learn"] = true }
  st.run(0.1); st.gui_set = nil; st.run(0.1)
  st.cc(TOP[1], 10); st.run(0.05); st.cc(TOP[1], 12); st.run(0.1)
  check(st.led(MUTE[1]) ~= nil, "learn взведён (мигание)")
  st.touched = { 2, 0, 1 }; st.run(0.3)                        -- track #2, fx 0, param 1 (Res)
  check(st.projext["MidiMixLua/bind_top1"] ~= nil and st.projext["MidiMixLua/bind_top1"]:find("{FX1}", 1, true), "привязка записана в проект")
  -- ручка управляет параметром (с подхватом: сначала далеко, потом проходит через 0.5)
  st.cc(TOP[1], 5); st.run(0.1)
  check(st.tracks[2].fxlist[1].params[2].val == 0.5, "далеко от значения: параметр не прыгает")
  st.cc(TOP[1], 90); st.run(0.1)
  check(near(st.tracks[2].fxlist[1].params[2].val, 90 / 127, 1e-3), "прошли значение: ручка управляет параметром")
  check((st.tracks[2].D_VOL == 1) and (st.tracks[1].sends[1] == nil), "треки микшера не тронуты")
  -- Mute открывает окно плагина, Rec выбирает трек
  press(st, MUTE[1]); st.run(0.1)
  check(st.tracks[2].fxlist[1].window == true, "Mute открыл окно плагина")
  check(st.led(MUTE[1]) == 127, "Mute-диод горит: окно открыто")
  press(st, MUTE[1]); st.run(0.1)
  check(st.tracks[2].fxlist[1].window == false, "Mute закрыл окно")
  press(st, REC[1]); st.run(0.1)
  check(st.selected == st.tracks[2] and st.led(REC[1]) == 127, "Rec выбрал трек, диод горит")
  -- play/stop: обе Bank
  st.note_on(BL); st.note_on(BR); st.run(0.05); st.note_off(BL); st.note_off(BR); st.run(0.1)
  check(st.commands[#st.commands - 1] == 40044 or st.commands[#st.commands] == 40044, "обе Bank = play/stop")
  -- Solo + Send All = в начало
  st.note_on(SOLO); st.run(0.05); press(st, SENDALL); st.note_off(SOLO); st.run(0.1)
  local went = false
  for _, c in ipairs(st.commands) do if c == "gostart" then went = true end end
  check(went, "Solo + Send All = в начало")
  -- Solo + ручка сбрасывает привязку
  st.note_on(SOLO); st.run(0.05); st.cc(TOP[1], 100); st.run(0.05); st.note_off(SOLO); st.run(0.1)
  check(st.projext["MidiMixLua/bind_top1"] == nil, "Solo + ручка сбросили привязку")
  local before = st.tracks[2].fxlist[1].params[2].val
  st.cc(TOP[1], 30); st.run(0.1); st.cc(TOP[1], 60); st.run(0.1)
  check(st.tracks[2].fxlist[1].params[2].val == before, "после сброса ручка ничего не меняет")
  -- обратно в микшер
  press(st, SENDALL); st.run(0.9)
  press(st, MUTE[1]); st.run(0.1)
  check(st.tracks[1].B_MUTE == 1, "в микшере Mute снова глушит трек")
  no_errors(st)
end)

test("окно: нулевая линия заметнее остальных меток, но не кричит", function()
  local st = setup({ gui = true, tracks = 4 })
  st.run(0.4)
  no_errors(st)
  local bright, thick = false, false
  for _, l in ipairs(st.gui_lines or {}) do
    if l.col == 0xFFFFFF8C then bright = true; if l.th == 1 then thick = true end end
  end
  check(bright and thick, "линия 0 дБ нарисована мягко: заметнее обычных меток, толщиной 1")
  local st2 = setup({ gui = true, tracks = 4, cfg = "return { fader_max_db = 6 }" })
  st2.run(0.4)
  local zero_text = false
  for _, t in ipairs(st2.gui_texts or {}) do if t == "0" then zero_text = true end end
  check(zero_text, "подпись 0 есть и при верхе +6")
end)

test("окно: подсказки при наведении есть и выключаются", function()
  local st = setup({ gui = true, tracks = 4 })
  st.run(0.4)
  no_errors(st)
  local has = false
  for _, t in ipairs(st.gui_tips or {}) do if t == "Pan. Bottom knob." then has = true end end
  check(has, "подсказка про pan есть")
  local off = setup({ gui = true, tracks = 4, cfg = "return { tooltips = false }" })
  off.run(0.4)
  no_errors(off)
  local n = 0
  for _, t in ipairs(off.gui_tips or {}) do if t == "Pan. Bottom knob." then n = n + 1 end end
  check(n == 0, "при tooltips = false подсказок на полосах нет")
end)

test("окно: вкладка Help со списком комбинаций", function()
  local st = setup({ gui = true, tracks = 4 })
  st.run(0.4)
  no_errors(st)
  local found = false
  for _, t in ipairs(st.gui_texts or {}) do if t == "Hold Bank Right + Mute" then found = true end end
  check(found, "в Help есть комбинация мастера")
end)

test("окно: вид MPC рисуется без ошибок, в том числе с панорамой, посылом и мастером", function()
  local st = setup({ gui = true, tracks = 5, cfg = "return { mixer_style = \"mpc\" }", before = function(s)
    s.tracks[1].I_SELECTED = 1
    s.tracks[2].D_PAN = -0.5
  end })
  st.peak = { [st.tracks[1].name] = 0.6, [st.tracks[2].name] = 1.4 }
  st.run(0.6)
  no_errors(st)
  local m, master = false, false
  for _, t in ipairs(st.gui_texts or {}) do if t == "MASTER" then master = true end end
  check(master, "в виде MPC есть мастер")
  local narrow = false   -- узкие метры 6 px
  for _, r in ipairs(st.gui_rects or {}) do if r.x2 - r.x1 == 6 then narrow = true end end
  check(narrow, "тонкие метры MPC нарисованы")
  -- переключение стиля из окна на ходу
  local live = setup({ gui = true, tracks = 3 })
  live.gui_set = { ["Mixer look##mixer_style"] = 1 }
  live.run(0.3); live.gui_set = nil; live.run(0.3)
  no_errors(live)
  check(live.ext and live.ext["MidiMixLua_settings/mixer_style"] == "mpc", "стиль MPC сохранён в настройках")
end)

test("окно: русский язык, шрифт подключается и снимается", function()
  local st = setup({ gui = true, tracks = 3, cfg = "return { language = \"ru\" }" })
  st.run(0.5)
  no_errors(st)
  local function has(str) for _, t in ipairs(st.gui_texts or {}) do if t == str then return true end end return false end
  check(has("МАСТЕР"), "МАСТЕР вместо MASTER")
  check(has("Hold Bank Right + Mute") == false and has("Держать Bank Right + Mute"), "в Help русские комбинации")
  check((st.font_created or 0) >= 1, "шрифт с кириллицей создан")
  check((st.font_push or 0) > 0 and st.font_push == st.font_pop, "шрифт ставится и снимается поровну (" .. tostring(st.font_push) .. "/" .. tostring(st.font_pop) .. ")")
  local en = setup({ gui = true, tracks = 3 })
  en.run(0.4)
  check((en.font_created or 0) == 0, "в английском шрифт не трогаем")
end)

print(string.format("\nИтого: %d проверок прошло, %d провалено", passes, fails))
return fails
