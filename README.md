English | [Русский](README.ru.md)

# AKAI MidiMix for REAPER

Use an **Akai MIDI Mix** as a full REAPER controller. One Lua ReaScript, no ReaLearn, OSC, CSI or C++ extension. LEDs follow REAPER, and an optional ReaImGui window shows what the controller is doing.

> Status: beta (v0.22). Tested against a mock REAPER (376 automated checks) and on one real MIDI Mix. Please report what differs on your setup.

## Features

**Mixing**
- Bank of up to 8 tracks (configurable). Bank Left / Bank Right move by a bank; hold for the first / last bank; Solo + Bank moves by one track.
- Faders = track volume (top = +12 dB, configurable). Master fader = master volume. Hold Bank Right: Mute = master mute, Solo = master solo, any bottom knob = master pan.
- Knobs: bottom row = pan, middle row = stereo width, top row = sends. Soft takeover (pickup) on every knob and fader, so tracks never jump.
- Per-track Mute, Solo (hold Solo + Mute), Rec arm. Solo tap = solo the whole bank. Solo + any Rec = rec arm the whole bank.
- Sends: the knob follows the send shown in the window. Hold Rec + tap Send All to switch to the next send of one track. Sends can be matched by destination name.
- Width only works on tracks in "stereo pan" mode; on other tracks the knob is ignored and the window shows "width n/a". The script never changes a track's pan mode unless you turn on "Allow switching tracks to stereo pan from the device" in Settings (then both Bank buttons together, or Solo + a middle knob, switch to stereo pan).

**Rec row modes** (double-tap Solo or use the window): Rec arm, Send mute, FX bypass for the whole chain.

**Instrument mode** (tap Send All or use the window): the 24 knobs control plugin parameters.
- Learn: click a cell in the window, touch a plugin parameter, done. Works for FX on any track and the master. Bindings are saved in the project.
- Mute opens the plugin window of that strip, Rec selects the track, both Bank buttons = play/stop, Solo + Send All = go to start, Solo + knob = forget the binding.

**Track types**: audio, instrument, bus, VCA, folder, separator. Detected from the track (including track layout) and can be overridden by hand. Separators are never controlled and can be skipped.

**Bank highlight in REAPER**: spacers above and below the bank, two marker tracks, track colouring, or nothing. Everything the script adds is tagged inside the project and cleaned up on stop or after a crash.

**Other**
- LEDs: Mute, Rec (by mode), Bank buttons (page indicator, pause), start-up and exit animations.
- Mixer follows the bank and the bank can follow the mixer scroll.
- Pause / resume and on/off from the controller (Send All).
- Settings screen with saved values and a config file, plus a debug log.

**Window** (needs ReaImGui, optional): a mixer view in the style of the Akai MPC mixer. Every strip shows track colour, selection, type icon, pan, width, send, a fader scale with stereo level meters and peak hold (after the fader and pan), dB readout, M / S / R buttons, folder bands. A MASTER strip shows the master fader. Tabs: Mixer, Instrument, Settings (collapsible groups). The window has an Akai Red title bar and never docks.

## Requirements

- REAPER with Lua ReaScript support. Developed and used on macOS; other versions and systems are untested.
- Akai MIDI Mix with **input and output enabled** in Preferences > MIDI Devices (output is needed for LEDs).
- Optional: [ReaImGui](https://github.com/cfillion/reaimgui) for the window (ReaPack > Browse packages).

## Installation

1. Options > Show REAPER resource path in explorer/finder > `Scripts`. Copy the contents of the `MIDI/` folder of this repository there: `AKAI MidiMix.lua` and the `midimix/` folder side by side.
2. Preferences > MIDI Devices: enable input and output for the MIDI Mix. "Enable input for control messages" is not needed.
3. Tracks that record from "All MIDI inputs" will receive the MIDI Mix notes. Change their input.
4. Actions > Show action list > New action > Load ReaScript > `AKAI MidiMix.lua` > Run. Add it to a toolbar for an on/off button.

If something does not work, run `AKAI MidiMix probe.lua`: it lights the LEDs one by one and logs what the device sends.

## Controls

| What | How |
|---|---|
| Volume | Faders |
| Pan / width / send | Bottom / middle / top knob rows |
| Mute | Mute button |
| Rec arm (or the current Rec row mode) | Rec button, acts on release |
| Solo one track | Hold Solo + Mute of the strip |
| Solo the bank | Solo, short tap |
| Rec the whole bank | Solo + any Rec |
| Clear all solo | Solo + Send All |
| Bank / first or last bank / one track | Bank Left, Bank Right / hold for 0.5 s, then release / Solo + Bank |
| Stereo pan for one track (opt-in) | Hold Solo, turn that track's middle knob |
| Stereo pan for the bank (opt-in) | Both Bank buttons |
| Next send of one track | Hold its Rec, tap Send All |
| Master mute / solo / pan | Hold Bank Right, then Mute / Solo / any bottom knob |
| Pause / resume | Send All, double tap |
| Rec row mode | Solo, double tap |
| Instrument mode | Send All, single tap (when `global_sends` is off) |

Send All has no hold detection in hardware (it only sends a burst of CC messages), so it supports tap and double tap only.

## Configuration

Create `midimix_config.lua` next to the script:

```lua
return {
  bank_size = 6,           -- strips per bank (1..8)
  highlight = "color",     -- spacers | markers | color | none
  sends_by_name = true,    -- match sends by destination name
  follow_mixer = true,     -- bank follows the mixer scroll
  separator_names = { "^%s*%-%-", "divider" },
  map = { mute = {2, 5, 8, 11, 14, 17, 20, 23} },  -- custom note map
}
```

All options and defaults are at the top of `midimix/settings.lua`. Values saved from the Settings tab override the file; "Reset to defaults" removes them.

## Project layout

```
MIDI/AKAI MidiMix.lua   entry point: loads the modules and runs the loop
MIDI/midimix/             settings, device, tracks, instrument, input, gui, highlight
MIDI/AKAI MidiMix probe.lua    hardware probe
tests/               mock REAPER and automated checks (python3 -I tests/run.py, needs lupa)
```

Modules share one environment (`CFG`, `S` and the helper functions), so a new feature goes into the module it belongs to.

## Known limits

- Send All reports only a CC burst: tap and double tap, no hold.
- Only Mute, Rec and Bank buttons have LEDs (hardware).
- FX bind targets: FX on tracks and master; item FX and input FX are not supported yet.
- Polling is about 30 Hz, so very fast moves can lose intermediate values.
- The Rec row mode is not remembered between runs.
- The LEDs show the send number for up to 16 sends per track (Rec LEDs 1..8, then blinking for 9..16). Sends above 16 still work, they are just not shown on the controller.
- Learned knobs (instrument mode) use pickup as well. Turn the knob slowly and carefully past the parameter's current value; if the parameter was changed somewhere else, the knob has to catch it again.

## Credits

Designed and tested by The Eighth. Most of the code was written with [Claude](https://claude.ai) (Anthropic).

## License

GPL-3.0-or-later, see [LICENSE](LICENSE).
