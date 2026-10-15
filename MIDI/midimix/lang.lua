-- @noindex
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (c) 2026 The Eighth
-- MidiMix module: window language. Loaded by AKAI MidiMix.lua into a shared environment.
-- L("English text") gives the Russian text when CFG.language = "ru", otherwise the text itself.

RU = {
  -- status line
  ["NO DEVICE"] = "НЕТ УСТРОЙСТВА", ["ACTIVE"] = "РАБОТАЕТ", ["PAUSED"] = "ПАУЗА",
  ["  bank %d/%d   tracks %d-%d / %d    send %d/%d"] = "  банк %d/%d   дорожки %d-%d / %d    посыл %d/%d",
  ["  bank %d/%d   tracks %d-%d / %d"] = "  банк %d/%d   дорожки %d-%d / %d",
  ["  Mode:"] = "  Режим:", ["  Rec row:"] = "  Ряд Rec:",
  ["Mixer"] = "Микшер", ["Instrument"] = "Инструмент", ["Settings"] = "Настройки", ["Help"] = "Подсказки",
  ["Rec arm"] = "Запись", ["Send mute"] = "Mute посыла", ["FX bypass"] = "Обход FX",
  ["Pause"] = "Пауза", ["Resume"] = "Продолжить", ["Close script"] = "Закрыть скрипт",
  -- track types
  ["Audio"] = "Аудио", ["Bus"] = "Шина", ["Folder"] = "Папка", ["Separator"] = "Разделитель",
  [" (set by hand)"] = " (задан вручную)", [" (automatic)"] = " (автоматически)", [" - click to change"] = " - клик меняет",
  -- strips
  ["(empty)"] = "(пусто)", ["not controlled"] = "не управляется", ["width n/a"] = "ширина: нет", ["no sends"] = "нет посылов",
  ["send"] = "посыл", ["MASTER"] = "МАСТЕР", ["master fader"] = "фейдер мастера", ["layer: Bank R"] = "слой: Bank R",
  ["Click the type under a strip to set it by hand (* = manual). Cycles through all types, then back to automatic."] =
    "Клик по типу под полосой задаёт его вручную (* = вручную). Перебирает все типы, потом снова авто.",
  -- hover hints
  ["Pan. Bottom knob."] = "Панорама. Нижняя ручка.",
  ["Width. Middle knob. Works only on tracks in stereo pan mode."] = "Ширина. Средняя ручка. Только на дорожках в режиме stereo pan.",
  ["Send level. Top knob. Hold Rec + tap Send All = next send of this track."] = "Уровень посыла. Верхняя ручка. Держать Rec + нажать Send All: следующий посыл этой дорожки.",
  ["Volume. Fader. Move the fader to the shown level first, then it takes over (pickup)."] = "Громкость. Фейдер. Сначала подведи фейдер к показанному уровню, потом он подхватит (pickup).",
  ["Mute. Mute button."] = "Mute. Кнопка Mute.",
  ["Solo. Hold Solo + the strip's Mute."] = "Solo. Держать Solo + Mute этой полосы.",
  ["Rec arm. Rec button, acts on release."] = "Запись. Кнопка Rec, срабатывает при отпускании.",
  ["Send mute. Rec button, acts on release."] = "Mute посыла. Кнопка Rec, срабатывает при отпускании.",
  ["FX bypass. Rec button, acts on release."] = "Обход FX. Кнопка Rec, срабатывает при отпускании.",
  ["Master volume. Master fader."] = "Громкость мастера. Фейдер Master.",
  ["Master pan. Hold Bank Right + a bottom knob."] = "Панорама мастера. Держать Bank Right + нижняя ручка.",
  ["Master mute. Hold Bank Right + Mute."] = "Mute мастера. Держать Bank Right + Mute.",
  ["Master solo. Hold Bank Right + Solo."] = "Solo мастера. Держать Bank Right + Solo.",
  -- instrument tab
  ["Top"] = "Верхний", ["Middle"] = "Средний", ["Bottom"] = "Нижний",
  ["touch a parameter"] = "тронь параметр", ["empty"] = "пусто",
  ["Learn mode (turn a knob, then touch a parameter)"] = "Режим learn (покрути ручку, потом тронь параметр)",
  ["Clear all"] = "Очистить всё",
  ["Click a cell, then touch a plugin parameter. x = forget. On the device: hold Solo and turn a knob = forget it. Mute = plugin window, Rec = select the track."] =
    "Клик по ячейке, потом тронь параметр плагина. x = забыть. На устройстве: держать Solo и повернуть ручку = забыть. Mute = окно плагина, Rec = выбрать трек.",
  -- settings
  ["(restart needed)"] = "(нужен перезапуск)", ["restart the script to apply"] = "перезапусти скрипт, чтобы применить",
  ["(needs restart)"] = "(нужен перезапуск)", ["Restart the script to apply the changed settings."] = "Перезапусти скрипт, чтобы применить изменённые настройки.",
  ["Dump track info (midimix_tracks.txt)"] = "Выгрузить данные о дорожках (midimix_tracks.txt)",
  ["Reset to defaults"] = "Сбросить настройки", ["Saved in REAPER, overrides midimix_config.lua"] = "Хранятся в REAPER, главнее midimix_config.lua",
  ["Window"] = "Окно", ["Knobs and faders"] = "Ручки и фейдеры", ["Sends"] = "Посылы", ["LEDs and animations"] = "Диоды и анимации", ["Other"] = "Прочее",
  ["Language"] = "Язык (Language)", ["Mixer look"] = "Вид микшера", ["Hover hints"] = "Подсказки при наведении",
  ["Classic (bars)"] = "Классический (полосы)", ["MPC 2.0 (round knobs)"] = "Как в MPC 2.0 (круглые ручки)",
  ["Window language. Needs a restart."] = "Язык окна. Нужен перезапуск.",
  ["Show a short hint when the mouse rests on a part of a strip"] = "Короткая подсказка, когда мышь стоит над частью полосы",
  ["Pickup tolerance"] = "Допуск подхвата", ["Pan centre snap"] = "Прилипание pan к центру", ["Fader top, dB"] = "Верх фейдера, дБ",
  ["0 = no tolerance. Bigger = easier to pick up a value, steps 0..127"] = "0 = без допуска. Больше = проще поймать значение, шаги 0..127",
  ["Width knob only on tracks in stereo pan mode"] = "Ширина только на дорожках в режиме stereo pan",
  ["On: the width knob ignores tracks in other pan modes (width would be inaudible there)"] = "Вкл: ручка ширины не трогает дорожки с другим режимом pan (там ширина не слышна)",
  ["Allow switching tracks to stereo pan from the device"] = "Разрешить переключать дорожки в stereo pan с устройства",
  ["Off (default): the script never changes a track's pan mode. On: Solo + middle knob and both Bank buttons set stereo pan."] =
    "Выкл (по умолчанию): скрипт сам не меняет режим pan. Вкл: Solo + средняя ручка и обе Bank ставят stereo pan.",
  ["Rec N + Send All = next send of one track"] = "Rec N + Send All = следующий посыл одной дорожки",
  ["Send All tap = next send of ALL tracks"] = "Send All = следующий посыл ВСЕХ дорожек",
  ["Match sends by name"] = "Искать посылы по имени",
  ["Tracks in a bank"] = "Дорожек в банке", ["Skip separator tracks (no dead slot)"] = "Пропускать разделители (без пустой полосы)",
  ["Empty track with a set height up to this = separator, px (0 = off)"] = "Пустая дорожка с заданной высотой до этой = разделитель, px (0 = выкл)",
  ["Show the bank with"] = "Показывать банк",
  ["Spacers"] = "Пробелами", ["Two red MidiMix separator tracks"] = "Двумя красными дорожками MidiMix", ["Tint the tracks red"] = "Подкраской дорожек", ["Nothing"] = "Никак",
  ["Tint strength"] = "Сила подкраски", ["Double tap Solo switches the Rec row mode"] = "Двойной Solo переключает режим ряда Rec",
  ["Bank follows mixer scroll"] = "Банк следует за прокруткой микшера", ["Scroll mixer to the bank"] = "Прокручивать микшер к банку",
  ["Meters show level after the fader"] = "Метры после фейдера", ["Meters follow pan (left/right levels)"] = "Метры следуют за pan (левый/правый)",
  ["LED circle on start"] = "Круг диодов при старте", ["Double blink on exit"] = "Двойное мигание при выходе",
  ["Solo blink, Hz"] = "Мигание solo, Гц", ["Bank blink, max Hz"] = "Мигание банка, макс. Гц", ["Send number on LEDs, s"] = "Номер посыла на диодах, с",
  ["Hold Bank = first/last bank, s"] = "Удержание Bank = первый/последний банк, с", ["Double tap time, s"] = "Время двойного нажатия, с",
  ["Debug log (midimix_log.txt)"] = "Журнал отладки (midimix_log.txt)",
  -- help tab
  ["Basics"] = "Основное", ["Banks"] = "Банки", ["Master"] = "Мастер", ["Sends and modes"] = "Посылы и режимы",
  ["Instrument mode"] = "Режим «инструмент»", ["Optional (Settings > Knobs and faders)"] = "По желанию (Настройки > Ручки и фейдеры)",
  ["Faders"] = "Фейдеры", ["Track volume (the Master fader = master volume)"] = "Громкость дорожки (фейдер Master = мастер)",
  ["Bottom knobs"] = "Нижние ручки", ["Pan"] = "Панорама",
  ["Middle knobs"] = "Средние ручки", ["Width (only on tracks in stereo pan mode)"] = "Ширина (только в режиме stereo pan)",
  ["Top knobs"] = "Верхние ручки", ["Send level (the send shown in the window)"] = "Уровень посыла (тот, что показан в окне)",
  ["Mute"] = "Mute", ["Mute the track"] = "Заглушить дорожку",
  ["Rec"] = "Rec", ["Rec arm, send mute or FX bypass (Rec row mode), acts on release"] = "Запись, mute посыла или обход FX (режим ряда Rec), срабатывает при отпускании",
  ["Hold Solo + Mute"] = "Держать Solo + Mute", ["Solo that track"] = "Соло этой дорожки",
  ["Solo, short tap"] = "Solo, коротко", ["Solo the whole bank (tap again = back as it was)"] = "Соло всего банка (ещё раз = как было)",
  ["Solo + any Rec"] = "Solo + любая Rec", ["Apply Rec to the whole bank"] = "Применить Rec ко всему банку",
  ["Solo + Send All"] = "Solo + Send All", ["Clear all solo"] = "Снять все соло",
  ["Bank Left / Bank Right"] = "Bank Left / Bank Right", ["Previous / next bank"] = "Предыдущий / следующий банк",
  ["Hold Bank 0.5 s, release"] = "Держать Bank 0,5 с и отпустить", ["Jump to the first / last bank"] = "Прыжок в первый / последний банк",
  ["Solo + Bank"] = "Solo + Bank", ["Move the bank by one track"] = "Сдвинуть банк на одну дорожку",
  ["Hold Bank Right + Mute"] = "Держать Bank Right + Mute", ["Mute the master"] = "Mute мастера",
  ["Hold Bank Right + Solo"] = "Держать Bank Right + Solo", ["Solo the master"] = "Solo мастера",
  ["Hold Bank Right + bottom knob"] = "Держать Bank Right + нижняя ручка", ["Master pan"] = "Панорама мастера",
  ["Hold Rec + Send All"] = "Держать Rec + Send All", ["Next send of that track"] = "Следующий посыл этой дорожки",
  ["Send All, double tap"] = "Send All, два нажатия", ["Pause / resume the script"] = "Пауза / продолжить",
  ["Solo, double tap"] = "Solo, два нажатия", ["Rec row mode: Rec arm > Send mute > FX bypass"] = "Режим ряда Rec: Запись > Mute посыла > Обход FX",
  ["Send All, single tap"] = "Send All, одно нажатие", ["Instrument mode on / off (when 'Send All tap = next send of ALL tracks' is off)"] =
    "Режим «инструмент» вкл / выкл (когда «Send All = следующий посыл ВСЕХ» выключено)",
  ["Instrument tab: click a cell"] = "Вкладка Instrument: клик по ячейке", ["Then touch a plugin parameter = mapped"] = "Потом тронь параметр плагина = привязка",
  ["Mute (a strip)"] = "Mute полосы", ["Open / close that strip's plugin window"] = "Открыть / закрыть окно плагина этой полосы",
  ["Rec (a strip)"] = "Rec полосы", ["Select the track"] = "Выбрать дорожку",
  ["Both Bank buttons"] = "Обе Bank вместе", ["Play / stop"] = "Play / стоп",
  ["Solo + knob"] = "Solo + ручка", ["Forget that mapping"] = "Забыть привязку",
  ["Hold Solo + middle knob"] = "Держать Solo + средняя ручка", ["Stereo pan for one track"] = "Stereo pan одной дорожки",
  ["Go to the start of the project"] = "В начало проекта",
  ["Both Bank buttons together"] = "Обе Bank одновременно", ["Stereo pan for the whole bank"] = "Stereo pan всему банку",
}

function L(s)
  if CFG.language == "ru" then return RU[s] or s end
  return s
end
