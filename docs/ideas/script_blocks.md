# Script Blocks — live strip blocks a person adds

Idea, noted 21/11/2026. The initial work of BL-029, after the phase 7 release. Parked by the owner (21/11/2026): "we
need to work on the scripting and scheduling logic more". The looks are settled: each was seen on the N4.

## What it is for
Information you can take in at a glance, refreshed every few minutes, on the N4's strip next to the built-in blocks:
the weather, the CPU temperature, a build status, a price. Each kind is a small script in a folder, not code in the
app (owner, 20/11/2026: new kinds are not built into the app). The script prints a line or two of text; the agent runs
it on a timer and draws the block.

Example: `curl -s "wttr.is/<City>?format=%c+%t"` prints `🌤️ +4°C`. The same URL without `format` prints six lines of
ANSI-coloured text art, about 30 characters wide: roughly 6 px per character on a block, unreadable. A script's output
has to be short; the block does not try to fit anything else.

## Decided (owner, 20–21/11/2026)
- **Scripts live in a folder, `blocks/`** beside the config (`~/.config/vsd/blocks/`; DeckOut Dev:
  `~/.config/vsd-dev/blocks/`), not as commands typed into a block: more organised, and one file can serve several
  blocks and presets.
- **The agent runs them**, not a LaunchAgent or cron job per script: no sprawl, nothing left running outside the app.
  An interim weather LaunchAgent was proposed and turned down for this reason (21/11/2026).
- **The script prints text; the agent draws.** A script never makes an image.
- **N4 strip blocks only** (176×112). Keys keep their fixed icons.
- **The look** (`docs/assets/script_blocks_mockup.png`, drawn with the agent's own fonts and colours):
  - The first two non-empty lines of output are shown, with ANSI escape codes removed and spaces trimmed.
  - Line 1 is large: bold rounded system font, 38 pt (34 pt when there is a line 2), shrunk a point at a time to fit
    160 px, down to 16 pt; still too wide, it is cut with "…".
  - Line 2 is optional: semibold, 16 pt down to 11 pt, grey `0x8E8E93`.
  - A label at the bottom names the block: semibold 12 pt, grey, upper case, at the height of PING and VOL. It comes
    from the script's name (`cpu-temp` → "CPU TEMP").
  - `| color=red`, `amber` or `green` at the end of a line colours that line with the load block's palette
    (`0xFF453A`, `0xFFB340`, `0x30D158`); default text `0xF5F5F7`. Neither xbar nor SwiftBar has amber, and both make
    green `#008000`, too dark for the deck: the names map to our palette.
  - Emoji are text: wttr's `%c` weather emoji, ✅, 🌡️ draw as Apple colour emoji with no extra mechanism.
  - `| icon=<name>` draws a symbol from the app's bundled Phosphor library (1,530 symbols, MIT; `cloud-sun`,
    `cloud-rain`, `check-circle`, `thermometer-hot`) left of line 1, in the line's colour, 44 pt (38 pt with a line
    2), 8 px before the text. The agent runs from the same bundle (`Contents/MacOS`), so it can load the fonts.
- **Failure has one fixed look for every script: a TV test card with the label.** Seven bars (`0xF0F0F0`,
  `0xFFFF00`, `0x00FFFF`, `0x00FF00`, `0xFF00FF`, `0xED1C24`, `0x0000FF`) from the top down to y 40; the reversed
  row (blue, black, magenta, black, cyan, black, white) at y 30–40; a black band below with the label in white. It
  replaces the reading, and the next good run replaces it. Turned down after seeing them on the deck: the last
  reading greyed with "· OLD" (not usable), an orange circle (calm, but C was preferred), the full card with its
  grey steps (no label, so two failing blocks look the same).
- **Not a script-supplied picture file** (xbar's and SwiftBar's `image=`): the most work for every author, and fixed
  pictures already have the `picture` block.

## Proposed, not agreed (CL, 21/11/2026)
The owner accepted these as a starting point ("not much" wrong) but wants the scripting and scheduling worked out
before building.
- **File name gives interval and label**, as in xbar: `name.<interval>.<ext>`, the last dot-segment before the
  extension, `s`/`m`/`h`; none or invalid → every minute. `weather.10m.sh`: label "WEATHER", every 10 minutes.
- **Running:** the file directly (executable bit and a `#!` line; the app never makes a file executable for you), with
  the person's login-shell environment as `shell:` actions have (Homebrew tools found), working folder `blocks/`.
  Cut off at 30 s, the limit actions have. The next run is timed from the end of the last, so runs never overlap.
- **A run fails when** the script exits non-zero, prints nothing, is cut off, or can't be started.
- **When it runs:** only while a block showing it is on the live preset of a connected deck; first run at once;
  paused while the Mac is locked, as the built-in live blocks are; an overdue script runs at unlock.
- **Folder checks**, as the config has: the folder and each script are owned by the person, not writable by group or
  others, not a symlink; otherwise the test card, and the log says why. Hidden files and subfolders are ignored.
- **Parameters:** an unknown `|` parameter or colour is ignored (as SwiftBar), not a failure (as xbar), so a typo
  gives plain text rather than the test card.
- **Config:** a strip block `"type": "script", "script": "<file name>"`, with the usual tap `action` and `step`.
  Silent-failure risk: the app saves the whole config, so its model must carry `script`, or the first edit in DeckOut
  drops it and the block goes dead without an error. A test must prove the app keeps it.
- **App:** the strip block's Shows menu lists the folder each time it opens, so a new script shows up without a
  relaunch (BL-029 first said "at the next launch").

## Open: scripting and scheduling
- A shortest interval, so a `weather.1s.sh` can't hammer a web service? Neither xbar nor SwiftBar has one.
- The same script on two blocks, or in two presets: one run shared (as internet blocks share one probe), or one each?
- Settings: one script per city, or one script with inputs (xbar's `<xbar.var>` plus a `.vars.json`; per-block
  arguments in the config)?
- Environment variables given to a script (which deck and block, why it runs: SwiftBar passes `SWIFTBAR_*`)?
- After a reload: run everything again, or keep each reading whose script didn't change? Stagger first runs?
- Keep scripts on presets that aren't live running, so a swipe shows a fresh reading at once?
- A script that keeps failing: retry sooner, or wait the full interval? Where its error output goes in the agent's log,
  and how much of it.
- A fixed 30 s limit, or never longer than the interval?
- Waking from sleep (BL-002): run overdue scripts, as SwiftBar does?
- `icon=` style: Bold or Fill by default, and a parameter for the other?
- What the app shows for a script block: the image the deck shows (`liveStrip`), the script's name, Test (run it now,
  show the output and exit status), "Open the blocks folder", Make Executable (as for `script:` actions)?
- Scripts run unattended with the person's rights and full network access: the same trust as a `shell:` action in the
  config. Is the folder check enough?
- Phase 7 and later moves: `blocks/` travels with the config and icons from `vsd-dev` to `vsd`.

## First slice (initial work of BL-029)
- A weather script as the first file in `blocks/`: `<city>.10m.sh` with `curl -sf -m 15
  "wttr.is/<City>?format=%c+%t"`; a failed fetch exits non-zero and shows the test card. Block 3 of the N4's Default
  preset shows it; a tap opens the city's BBC Weather page (`url:`).
- The agent: the runner (interval from the name, no overlap, 30 s limit, login environment, paused while locked, only
  on the live preset), the folder checks, the drawing (text, `color=`, test card).
- The config: a `script` block, set by hand, as the swipe's `next_preset` was; the app keeps the field when it saves and
  shows the block as the deck draws it, with no Shows entry yet.
- Later: `icon=`, the Shows menu, Test, the open questions above.
- Touches `StripBlockType` and `StripBlockConfig` (`Config.swift`), `StripRenderer`, `Daemon.swift`, `LayoutPlan`,
  the app's strip editor; reuses the config's ownership checks (`ConfigFile`) and the action runner's environment and
  time limit.

## Other findings
- CPU temperature needs a helper: macOS has no command that reads it without root (`powermetrics` needs sudo; `pmset
  -g therm` gives warning levels only). `macmon` (Homebrew) reads it without root:
  `macmon pipe -s 1 | python3 -c 'import json,sys; print(round(json.load(sys.stdin)["temp"]["cpu_temp_avg"]))'`.
- A picture block fits its image inside a 4 px margin (×0.929), so a full-block image shows smaller than a live block
  drawn by the agent; the mockups on the deck were drawn ×1.077 to make up for it.

## Prior art (read at source, 21/11/2026)
xbar at `d624239` (https://github.com/matryer/xbar/blob/d624239058997c80118eaebe2e7f8331b3c765e0/) and SwiftBar at
`97f4f87` (https://github.com/swiftbar/SwiftBar/blob/97f4f87dc90e668c7829f1ee4a6fb7988c47bc73/). Read by CL: both
Interval cells, both Running cells, xbar's Overlap and SwiftBar's Sleep. The rest come from a research agent's reading
of the same commits, not re-checked.

| | xbar | SwiftBar |
|---|---|---|
| Interval | last dot-segment before the extension; `ms` `s` `m` `h` `d`; default 1 min (`pkg/plugins/refresh_interval.go` L113–145) | smallest of all segments; default never (`SwiftBar/Plugin/ExecutablePlugin.swift` L72–74) |
| Running | `./<file>` directly, in the plugin folder; 2 min timeout (`pkg/plugins/plugin.go` L163–167, L293–300) | through `zsh -l -c` by default (`SwiftBar/Utility/RunScript.swift` L133–145); no timeout found |
| Overlap | one loop per plugin; the next run waits for the last (`plugin.go` L218–235) | timer re-armed when a run ends |
| Sleep | not handled | stops plugins on sleep, starts them on wake (`SwiftBar/AppDelegate.swift` L232–255) |
| Lines | all lines before `---`, rotating every 5 s | the same |
| `\|` parameters | unknown key fails the plugin; `color=` CSS names or hex | unknown keys ignored; light,dark colour pairs; `sfimage=` names an SF Symbol |
| Errors | "⚠️ name" in the bar, stderr in the menu | an error symbol, stderr in a popover; ⚠️ when stale for two intervals |
| Folder | re-read at launch and on Refresh All; no checks | watched (kernel events, 0.5 s debounce); makes files executable; no ownership checks |
| Screen lock | not handled | not handled |
