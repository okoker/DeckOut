# StreamDeckController — Requirements

## Overview
Lightweight macOS daemon (Swift) that drives budget stream decks over USB HID: the TreasLin N3 (VID 0x5548,
PID 0x1001) and the MiraBox Stream Dock N4 (VID 0x6602, PID 0x1001). One daemon drives every supported deck that is
plugged in, each with its own layout; both may be connected at once. Reads button/knob events, maps them to
configurable actions. Set up with the DeckOut app (`docs/reference/app.md`; on local branches until the owner's UAT),
or by hand in the JSON file. macOS 15 or later, Apple Silicon. The program is `DeckOutAgent` (built by `swift build`); a hand install from the
README keeps it under its old name, `StreamDeckController`.

## Devices
Event codes overlap between the decks with different meanings, so each deck's input is decoded with its own map.

### TreasLin N3
- **6 LCD buttons** (event codes 0x01–0x06, press + release)
- **3 round buttons** (event codes 0x25, 0x30, 0x31, press + release)
- **3 rotary knobs** (each: clockwise, counter-clockwise, press + release)
  - Big knob: rotate 0x50/0x51, press 0x35
  - Small knob 1: rotate 0x90/0x91, press 0x33
  - Small knob 2: rotate 0x60/0x61, press 0x34

### MiraBox Stream Dock N4
Maps verified on the unit (18/11/2026); details in `docs/design/n4_support.md`.
- **10 LCD keys**, 2 rows of 5: top row 0x01–0x05, bottom row 0x06–0x0A (press + release)
- **Touch strip** of 4 image blocks: tap 0x40–0x43 (one frame, no release); swipe 0x39 (no direction);
  0x38 (touch outside the blocks) is ignored
- **4 push-knobs**, left → right: rotate clockwise / anticlockwise, press (no release)
  - Knob 1: 0xA1 / 0xA0, press 0x37 · Knob 2: 0x51 / 0x50, press 0x35
  - Knob 3: 0x91 / 0x90, press 0x33 · Knob 4: 0x71 / 0x70, press 0x36

## Protocol (proven working, same on both decks)
- USB HID vendor interface: usage page 0xFFA0, usage 0x0001
- Packet size: 1025 bytes (0x00 report ID + 1024 data)
- Init sequence: CRT DIS → CRT LIG → CRT STP → CRT CLE
- Keepalive: CRT CONNECT every 5 seconds
- Input: 512-byte packets prefixed with "ACK\0\0OK\0\0", event at byte[9], state at byte[10]
- macOS requires CFRunLoop running for IOKit HID input delivery

## Configuration
One JSON file: `--config <path>`, else the first that exists of `~/.config/vsd/config.json` and `config.json` next to
the executable, else `~/.config/vsd/config.json`. Read at start-up and re-read on `SIGHUP` or the reload notification
(`--post-reload`); a reload that fails the security checks or doesn't parse keeps the previous config.
- **Security checks on every read:** the file must not be a symlink, must be owned by the user and not writable by
  group or others.
- **No usable config at start-up** (missing, refused or not parseable): the daemon still runs, with no decks set up
  (they stay blank), and logs why ("No config yet at <path>", "Config refused: …", "Config doesn't load: …"). A later
  reload that loads replaces the blank config. It never exits for want of a config: under launchd's `KeepAlive` that
  would crash-loop.
- **Saving (for the config app):** written atomically (a temp file in the same folder, then `rename`) at mode 0600,
  creating the folder at 0700 if needed. The first save over an existing file copies it to
  `config.json.before-app` once, so a rollback to the v1.0.0 daemon (which can't read presets) has the old file.

### Structure
Shared settings at the top; one section per deck under `decks`. Each deck holds its presets (the keys, and on the
N4 the strip) and names the live one in `active_preset`; knobs, brightness, the swipe and the lock photo belong to the
deck. Full example: `config.example.json`.
```json
{
  "displays": [ { "name": "Left", "serial": "AN_SERIAL_FROM_M1DDC" } ],
  "decks": {
    "n3": {
      "brightness": 50,
      "knobs": { "big": { "rotate": { "action": "system_volume", "step": 5 }, "press": { "action": "system_mute_toggle" } } },
      "presets": [
        { "name": "Default",
          "buttons": { "lcd_1": { "action": "shell:open -a Safari", "icon": "/Applications/Safari.app/Contents/Resources/AppIcon.icns" } } }
      ],
      "active_preset": "Default"
    },
    "n4": {
      "brightness": 50,
      "knobs": { "knob_1": { "rotate": { "action": "system_volume", "step": 5 }, "press": { "action": "system_mute_toggle" } } },
      "swipe": { "action": "none" },
      "lock_photo": { "path": "/path/to/photo.jpg", "zoom": 1.5, "offset_x": 0, "offset_y": 0.2 },
      "presets": [
        { "name": "Work",
          "keys":  { "key_1": { "action": "shell:open -a Notes", "icon": "/path/to/icon.icns" },
                     "key_2": { "action": "system_volume", "step": -5 } },
          "strip": {
            "1": { "type": "internet", "host": "one.one.one.one", "arrow_ms": 2, "timeout_s": 3, "action": "shell:…" },
            "2": { "type": "load", "action": "shell:open -a 'Activity Monitor'" },
            "3": { "type": "empty" },
            "4": { "type": "volume" }
          } },
        { "name": "Music", "keys": { "key_1": { "action": "shell:open -a Music" } }, "strip": {} }
      ],
      "active_preset": "Work"
    }
  }
}
```
- **N3:** buttons `lcd_1`–`lcd_6`, `btn_1`–`btn_3` (per preset); knobs `big`, `small_1`, `small_2`. `brightness` and
  `knobs` are required.
- **N4:** keys `key_1`–`key_5` (top row, left → right), `key_6`–`key_10` (bottom row) and strip blocks `"1"`–`"4"` left
  → right (per preset); knobs `knob_1`–`knob_4` left → right. `brightness` is required; `knobs`, `swipe` and
  `lock_photo` may be left out, and a preset may leave out `keys` and `strip`.
- **Presets:** at least one, each with a name; an empty name or two presets with the same name make the file invalid.
  `active_preset` names the live one; a name no preset has falls back to the first, with a log line. The load
  summary prints `Preset: Work (2 presets)` per deck.
- **Steps on presses:** a key, knob press, strip block or swipe may carry a signed `step` (`5` up, `-5` down) for the
  stepped actions (`system_volume`, `display_brightness`, `zr7_volume`). A knob turn's step is its `rotate.step`
  (default 1) times the turn's direction.
- **Strip block `type`:** `internet` (`host`, default `one.one.one.one`, also for an empty or blank one; `arrow_ms`, default 2, 0 or more; `timeout_s`, default 3, 0.1–60 — out-of-range numbers are refused at load),
  `load`, `volume`, `picture` (shows `icon`), `empty`. A tap runs the block's `action`. An unknown type makes the whole
  file invalid.
- **`swipe.action`:** one action for a swipe on the strip. **`lock_photo`:** shown across the N4 while the Mac is locked.
  Either a path (filled and centred) or `{ "path", "zoom", "offset_x", "offset_y" }`: `zoom` 1–10 on top of the fill
  (outside that range the file is invalid), offsets as fractions of the 800×464 face (positive `offset_y` moves the
  photo down). The photo always covers the face: an offset that would show an edge is clamped. Written as the object.
- **Older files still load:** a deck section without `presets` reads as one preset named "Default", made from its
  `buttons` (N3, then required) or `keys` + `strip` (N4). A file with no `decks` key is read as the N3 section —
  top-level `brightness`, `buttons`, `knobs` (the v1.0.0 layout). When `decks` is present, top-level
  `brightness`/`buttons`/`knobs` are ignored.
- **Written form:** the daemon library writes the file pretty-printed with sorted keys, always in the `decks` form
  with `presets` and `active_preset`, and only keys it knows; `host`, `arrow_ms` and `timeout_s` only for `internet`
  blocks.

## Actions

| Action | Description |
|--------|-------------|
| `shell:<command>` | Execute shell command |
| `key:<shortcut>` | Simulate keyboard shortcut (e.g. `cmd+shift+4`); needs Accessibility |
| `app:<path>` | Open an app: an absolute path ending `.app` |
| `url:<URL>` | Open a web address (any `http`/`https` URL with a host, path and query included) in the default browser |
| `open:<path>` | Open a file or folder (absolute path) with its default app |
| `script:<path>` | Run a program or script (absolute path) directly, no shell: the path goes to the program as given |
| `shortcut:<name>` | Run one of Apple's Shortcuts (`/usr/bin/shortcuts run <name>`) |
| `media_play_pause` / `media_next` / `media_previous` | The Mac's media keys, so they control whatever is playing; need Accessibility |
| `system_volume` | Adjust macOS system volume by ±step per tick (on a key, knob press, tap or swipe: by its `step`) |
| `system_mute_toggle` | Toggle system mute (daemon tracks state, syncs with actual) |
| `zr7_volume` | Adjust ZR7Player volume by ±step per tick (interface TBD) |
| `zr7_mute_toggle` | Toggle ZR7Player mute (interface TBD) |
| `display_brightness` | Adjust external monitor brightness by ±step per tick (DDC/CI via m1ddc) |
| `display_brightness_cycle` | Cycle brightness target: All → per-display → All (30 s auto-revert) |
| `none` | No action |

A bad payload (`app:` without `.app`, a relative `open:`/`script:` path, a `url:` that isn't http(s), an empty
`shortcut:`) or an unknown action logs a warning when pressed and does nothing. `key:` and media actions log one warning
at load when Accessibility isn't granted.

**How commands run** (`shell:`, `script:`, `shortcut:` and the environment read; `m1ddc` still runs through
Foundation's `Process`):
- With the user's own shell environment: the login shell (`/bin/zsh` unless the user database says otherwise) is
  started as login + interactive, its environment read between two random markers, and kept. Read at start-up and on
  reloads from outside (`SIGHUP`, `--post-reload`, one read per merged burst); not on the config app's own saves.
  If the shell hangs, waits for input or prints no markers, it gets SIGTERM after 10 s (SIGKILL a second later; the
  answer is in by about 12 s at worst) and the daemon falls back to its
  own environment with `/opt/homebrew/bin` and `/usr/local/bin` added to PATH (a later failed read keeps the last good
  environment). The log says `Shell environment: resolved` or `fell back (<why>)`.
- `shell:` runs `/bin/zsh -c <command>`; `script:` runs the file itself (it must be executable); `shortcut:` runs
  `/usr/bin/shortcuts run <name>`. Each with stdin `/dev/null`, at most 30 s: then the command's whole process group gets
  SIGTERM, and SIGKILL 1 s later. Children start with default signal handling and only stdin/stdout/stderr inherited.
  Commands run side by side: a slow one (or a Test run from the config app) never holds up the next press.
- stdout and stderr are each capped at 64 KB. A press logs a failure, stderr and a non-zero exit; stdout is not
  logged (the config app's Test button shows it).

## External Monitor Brightness (DDC/CI)

macOS has no native support for controlling brightness on non-Apple external displays. The built-in brightness keys and Control Centre slider only work on the internal panel and Apple-branded monitors (e.g. Apple Studio Display, Pro Display XDR). Third-party displays — including high-end LG, Dell, and Samsung panels connected via USB-C or DisplayPort — are invisible to macOS brightness controls.

The industry-standard workaround is **DDC/CI** (Display Data Channel / Command Interface), a protocol where the OS sends commands over the display cable to adjust settings like brightness and contrast. On Apple Silicon Macs, [`m1ddc`](https://github.com/waydabber/m1ddc) is the most reliable DDC/CI CLI tool (works on M1–M4, all variants despite the name).

### How it works in this daemon

- Optional `displays` array in config maps friendly names to monitor AN Serials (from `m1ddc display list detailed`)
- At startup, the daemon resolves serials to current m1ddc display numbers (handles reboot shuffling)
- Knob rotation fires async `m1ddc set luminance` calls with debouncing (80 ms) to keep the knob responsive
- Knob press cycles the brightness target: All connected displays → each display individually → back to All
- After 30 seconds of inactivity, the target auto-reverts to All
- A floating HUD overlay (80 pt text, smaller when a message wouldn't fit) appears on all screens showing current
  brightness and target mode
- Brightness is read from the monitor on the first turn after start-up, a reload, 30 s idle or a failed write, then
  tracked during active use (start-up only finds the monitors: a reading taken then could be stale by the first turn)
- A monitor that gives no valid reading (m1ddc fails, or prints something outside 0–100) is never moved from a guess:
  the turn leaves it alone, the HUD says "Left: Monitor Error" (by its name), and the next turn reads it again; the
  other monitors still move

### Known DDC/CI quirks

- LG monitors do **not** show their native OSD bar for DDC/CI brightness changes (only for physical button presses) — hence the custom HUD
- Stock `m1ddc get luminance` (1.3.1 and 1.3.2) reads the reply 10 ms after asking and decodes it unchecked: on the
  LG HDR 4K pair about half of back-to-back reads came back empty, shifted or as an echo of the request, printed as
  `0` (or 41984) with exit 0. DeckOut's patched m1ddc waits 50 ms, checks the reply and asks again (up to 4 times)
- `m1ddc get input-alt` (LG's alternate address) never gets a real reply on that LG; the patched m1ddc says so
- `m1ddc chg luminance` (relative change) is unreliable on some LG panels — the daemon uses absolute `set luminance` instead
- Display numbers from `m1ddc` can change across reboots — the daemon matches by serial number, not display number

### Dependency

`m1ddc` (MIT, version 1.3.1, patched: reads wait 50 ms, are checked and asked again; `Vendor/m1ddc/README.md`)
ships inside DeckOut, built from the vendored source (`Vendor/m1ddc`) into
`DeckOut.app/Contents/Helpers/m1ddc`; the agent uses that copy, else Homebrew's (`brew install m1ddc`, for a hand
install). Without either, all other features work — brightness actions log a warning.

## LCD Icons
- Optional `icon` field per LCD key in config; sent to the deck as JPEG via CRT BAT (header with length and wire
  slot), 1024-byte chunks, then STP
- N3: 85×85 JPEG, turned 90° + 180°, shifted −9 / +8 px to sit centred on the LCD. No icon = black
- N4: keys 112×112 JPEG turned 180°, no offset; strip blocks 176×112 turned 180° (`picture` blocks show an icon).
  Slots: top-row keys 11–15, bottom-row keys 6–10, strip blocks 1–4. No icon = black
- An optional `tile` per key records how the app generated its icon (text or a library symbol on a colour) so it can
  edit it again; the agent ignores it and draws `icon`

## Daemon Behaviour
- Runs as background process (launchd plist for auto-start)
- Connects to every supported deck on startup; each reconnects on USB replug while the others keep running
- Sends init sequence to each deck, then listens for events
- Sends CONNECT keepalive to every connected deck every 5 seconds
- On button press: executes mapped action (ignores release events for buttons)
- On knob rotate: applies ±step for each tick
- On knob press: executes the knob's press action
- Reloads the config on `SIGHUP` or the distributed notification `com.streamdeck.controller.reload`
  (`DeckOutAgent --post-reload` posts it), then redraws in place — no clear, so nothing blinks — sending only
  the screens whose image changed. A reload reads every icon file again and renders it again only when its bytes
  changed (not its date or size), so a script that rewrites its icon at the same path and posts a reload shows the
  new picture; live blocks are drawn from their latest reading. A slot with nothing set is drawn black.
  Connect and unlock send every screen. A reload that fails keeps the previous config and the deck unchanged.
  Requests within 0.15 s of the first merge into one reload. The monitor control is built off the main thread at
  start, and again when `displays` changes or on a reload from outside (`SIGHUP`, `--post-reload`), which finds
  monitors plugged in or `m1ddc` installed since start; the config app's own saves reuse it. Until it is ready,
  brightness actions log "monitors not ready yet"
- `--config <path>` loads that file instead of searching (development); the same security checks apply.
  `--config` without a path exits with an error (a bad invocation, not a missing config)
- Starts with the decks blank, logging why, when the config is missing or unusable (see Configuration)
- `--mach-service <name>` serves the config app over XPC on that launchd Mach service (the agent plist names it;
  without the flag there is no listener). Calls: `status` (version, connected decks, live presets, config problem,
  shell environment), `reload`, `test` (run one action as a press would, minus the lock check; replies with exit
  status, stdout, stderr or the error), `showLockPhoto` (a framing, or nil for the layout; the preview ends by itself
  when the connection that set it goes, e.g. the app quits or crashes in photo mode), `refreshEnvironment`,
  `restart` (replies, then exits 0.3 s later; launchd's KeepAlive starts the binary now in the bundle) and
  `liveStrip` (the images the N4's live strip blocks show, keyed by block, as drawn) and `requestAccessibility` (asks
  macOS to list the agent under Accessibility; `status` reports whether it's allowed); the app hears `statusChanged`
  on deck connect / remove, reloads and environment reads, and `liveStripChanged` once per redraw that gives live
  blocks new images, once it has asked for `status` on that connection (asking signs it up, so a peer XPC refuses
  hears nothing; with no app signed up, neither is built).
  Payloads are JSON of DeckCore's types; a request that doesn't decode gets the error "bad request".
  Only DeckOut's own app may connect, checked by
  XPC before any call runs: signed with a Developer ID, a peer with the agent's own team id and the app's bundle id;
  ad hoc (development), the exact app binary in the agent's bundle, pinned by its code hash read from disk at each
  connection. Outside DeckOut.app, or when no requirement can be built, every connection is refused (the decks still
  work). The app checks the agent the same way when signed, and by its identifier when ad hoc
- While the app's lock-photo preview is up, the photo is decoded once (not per framing sent during a drag)
- `--show-lock-photo` keeps the N4's lock photo, as framed at start, up while unlocked (development: lining up the
  panel rectangles). The same preview is switchable at run time for the config app's photo mode
- Logs to stdout (a hand install's plist sends it to `~/Library/Logs/StreamDeckController.log`). Inside DeckOut,
  started by launchd with `--mach-service`, it writes `~/Library/Logs/DeckOut/agent.log` (dev variant:
  `~/Library/Logs/DeckOut Dev/agent.log`), moved to `agent.log.1` at start when over 5 MB
- Inside DeckOut the config is `~/.config/vsd/config.json` (dev variant: `~/.config/vsd-dev/config.json`), unless
  `--config` names another; a hand install searches as above
- `status` also reports the build (`CFBundleVersion`) the agent started with; version and build are read at launch
- A reload from outside (`SIGHUP`, `--post-reload`) logs the whole config; one the app asks for logs one line
- Graceful shutdown on SIGTERM/SIGINT

## Lock Behaviour (all decks unless stated)
- Lock state comes from the distributed notifications `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`
  (instant), re-checked against the session's `CGSSessionScreenIsLocked` on every 5 s tick and before acting on a
  key, strip tap or swipe — the lock notification can fire when a screen saver merely starts
- **While locked:** keys, strip taps and swipes do nothing. Knobs run only the built-in actions (`system_volume`,
  `system_mute_toggle`, `zr7_volume`, `zr7_mute_toggle`, `display_brightness`, `display_brightness_cycle`);
  `shell:`, `key:`, `app:`, `url:`, `open:`, `script:`, `shortcut:` and the media keys never run from any control.
  Live strip readings pause
- **N4 with `lock_photo`:** on lock the photo is drawn across all 14 slots (scaled to fill the deck's face, then
  zoomed and moved by its framing, each slot cut at its measured position); on unlock the layout is redrawn. Without a photo, every deck keeps its
  layout, inert
- Keep the photo in `~/.config/vsd/`: macOS asks before a background program reads Desktop, Documents, Downloads
  or iCloud Drive, and an unsigned daemon loses that permission on every rebuild

## Safety Constraints
- **HID isolation**: MUST only open the vendor interface (usage page 0xFFA0, usage 1) of the supported decks — N3 VID 0x5548 / PID 0x1001 and N4 VID 0x6602 / PID 0x1001. Never the decks' keyboard interfaces. Never enumerate, open, or interfere with any other HID device (keyboards, mice, trackpads, etc.)
- **No kernel driver manipulation**: MUST NOT unload, detach, or modify any macOS kernel drivers or kexts. The daemon operates purely in userspace via IOKit HID API
- **USB passivity**: MUST NOT send USB control transfers, reset devices, or alter USB configuration of any device other than the target deck
- **launchd safety**: The launchd plist MUST only manage this daemon's own process. No modification of other launchd jobs, plists, or system services. Use `LaunchAgents` (user-level), never `LaunchDaemons` (system-level)
- **Shell command sandboxing**: `shell:` actions run with the user's normal permissions. The daemon itself requires no elevated privileges (no sudo, no root)
- **Graceful failure**: If the device is not connected, the daemon waits quietly and retries. No error storms, no resource hogging, no interference with other USB devices

## The App (DeckOut)
How it works: `docs/reference/app.md`. Contracts:
- Runs only as `/Applications/DeckOut.app` (the dev variant, `io.github.okoker.deckout.dev`, anywhere); registers its
  agent with `SMAppService.agent` from `Contents/Library/LaunchAgents`; never opens a USB device itself
- Talks to the agent only over XPC, each side checking the other's code signature; restarts an agent of another
  build once per launch
- The app's "running" indicator comes from the agent's `status`, never from `SMAppService.status`
- Every control of both decks is set from the app: keys, N3 buttons, knobs (turn + press) and strip blocks (what
  they show + tap); presets (switch, new, duplicate, rename, delete) and brightness from the toolbar. Knob turns offer
  only stepped actions. The app asks for Accessibility when a shortcut or media key is set up; the agent never asks
  on its own
- The N4's lock photo is chosen, moved and zoomed in the window's photo mode, previewed on the real N4 while editing;
  the app keeps its own copy of the photo in the config folder
- Keys can show generated text or library-symbol icons (Phosphor, MIT, shipped in the app)
- First run: with the hand-installed `com.streamdeck.controller` present, the app asks before registering its own
  (two controllers would both act on every press); retiring it is the person's click and reversible
- Settings: monitors for the brightness keys (named, ordered, told apart by place), the deck controller's state, and
  removal (Stop and Remove: out of launchd and Login Items; the config stays)
- Every change in the app is saved whole and atomically, then the agent is asked to reload; undo puts back the whole
  previous config. A config that wouldn't load back is never written. A hand edit made while the app is open is built
  on, not overwritten; a hand edit that doesn't load is never saved over

## Non-Goals (for now)
- No CLI config tool
- Hot-reload supported via SIGHUP (`killall -HUP StreamDeckController` for a hand install) or `DeckOutAgent --post-reload`
- No switching presets from the deck itself: the live preset is the config's `active_preset`
- No Windows/Linux support
