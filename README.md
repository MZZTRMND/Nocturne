# nocturne

A late-night groove synth for macOS. Choose a style and press Space. Nocturne plays a
looping five-part track that you shape with knobs and faders, play over on the
keyboard, and record to WAV.

Everything is generated in real time by its own synth engine. There are no samples.

## Styles

| Style | Key | Parts |
|---|---|---|
| Trip-Hop | D minor | Drums, Sub, Bass, Rhodes, Haze |
| Industrial | E minor | Machine, Sub, Grind, Pad, Drone |
| Dreamy | A minor | Drums, Sub, Arp, Pad, Tape |
| Synth | C minor | Drums, Drone, Pulse, Piano, Static |
| Ambient | B minor | Metal, Drone, Low, Pad, Wind |
| D&B | F minor | Break, Sub, Bass, Keys, Dust |

Each style loads with its own tempo, swing, tone, grit and space. **Reset** in the presets menu
puts everything back to how the style was loaded.

## Features

- **Mixer.** Five channel faders. Click a track's name to mute it, double-click a
  fader to reset it, and press ⇧⌘M to mute everything.
- **Knobs.** Tempo, swing, tone, grit and space. Drag up or down to turn,
  double-click to reset.
- **Piano.** Play C4–E5 from the computer keyboard (`A`–`;` for white keys, `W E T Y U O P`
  for black keys) using the current keys sound.
- **Manual mode.** Change each part's sound and pattern, and set the bar it comes in on.
- **Step editor.** Write your own drum beat and bass line bar by bar. Click a chord name
  to swap it, and the bass follows.
- **Text prompts.** Describe the music in the prompt bar and the on-device Apple
  Intelligence model sets up every part. Nothing leaves your Mac.
- **Recording.** ⌘R captures the final mix (after reverb, delay and the master
  limiter) to a 24-bit WAV file.
- **Projects.** Save and open `.nocturne` files with ⌘S and ⌘O. The last session is
  restored on launch.

## Shortcuts

| Keys | Action |
|---|---|
| Space | Play / stop |
| ⌘R | Record / stop recording |
| ⌘S / ⌘O | Save / open project |
| ⇧⌘M | Mute / unmute all |
| ⌘1 – ⌘6 | Switch style |
| ⌘/ | Show help |

## Requirements

- macOS 26 or later
- Swift 6.2 toolchain (Xcode 26)
- Apple Intelligence enabled, for text prompts only

## Build

```bash
Scripts/make-app.sh
open Nocturne.app
```

`Scripts/make-app.sh --test` builds **Nocturne-Test.app** instead. It has a separate
bundle id (`com.nocturne.synth.test`) and its own saved data, so new features can be
tried without touching the main app.

You can also run it straight from SwiftPM:

```bash
swift run -c release Nocturne
```

## Debug hooks

- `Nocturne --render-test <dir>` renders every style offline and reports levels,
  per-track dB, brightness and NaNs.
- `NOCTURNE_RECORD_TEST="<seconds>|<file.wav>"` records through the live engine. Pass it
  with `open -n --env … Nocturne-Test.app`.
- `--snapshot <file.png>` saves the window's layout offscreen. It doesn't show the
  toolbar, popovers or the real glass effect.
