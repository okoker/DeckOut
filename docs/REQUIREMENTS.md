# StreamDeckController — Requirements

## Overview
Lightweight macOS daemon (Swift) that drives budget stream decks over USB HID: the TreasLin N3 (VID 0x5548,
PID 0x1001) and the MiraBox Stream Dock N4 (VID 0x6602, PID 0x1001). One daemon drives every supported deck that is
plugged in, each with its own layout; both may be connected at once. Reads button/knob events, maps them to
configurable actions. No GUI — configured via JSON file.

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
One JSON file: `~/.config/vsd/config.json`, or `config.json` next to the executable. Read at start-up and re-read on
`SIGHUP`; a reload that fails the security checks or doesn't parse keeps the previous config.

### Structure
Shared settings at the top; one section per deck under `decks`. Full example: `config.example.json`.
```json
{
  "displays": [ { "name": "Left", "serial": "AN_SERIAL_FROM_M1DDC" } ],
  "decks": {
    "n3": {
      "brightness": 50,
      "buttons": { "lcd_1": { "action": "shell:open -a Safari", "icon": "/Applications/Safari.app/Contents/Resources/AppIcon.icns" } },
      "knobs": { "big": { "rotate": { "action": "system_volume", "step": 5 }, "press": { "action": "system_mute_toggle" } } }
    },
    "n4": {
      "brightness": 50,
      "keys":  { "key_1": { "action": "shell:open -a Notes", "icon": "/path/to/icon.icns" } },
      "knobs": { "knob_1": { "rotate": { "action": "system_volume", "step": 5 }, "press": { "action": "system_mute_toggle" } } },
      "strip": {
        "1": { "type": "internet", "host": "one.one.one.one", "arrow_ms": 2, "timeout_s": 3, "action": "shell:…" },
        "2": { "type": "load", "action": "shell:open -a 'Activity Monitor'" },
        "3": { "type": "empty" },
        "4": { "type": "volume" }
      },
      "swipe": { "action": "none" },
      "lock_photo": "/path/to/photo.jpg"
    }
  }
}
```
- **N3:** buttons `lcd_1`–`lcd_6`, `btn_1`–`btn_3`; knobs `big`, `small_1`, `small_2`. `brightness`, `buttons` and
  `knobs` are required.
- **N4:** keys `key_1`–`key_5` (top row, left → right), `key_6`–`key_10` (bottom row); knobs `knob_1`–`knob_4` left →
  right; strip blocks `"1"`–`"4"` left → right. `brightness` is required; `keys`, `knobs`, `strip`, `swipe` and
  `lock_photo` may be left out.
- **Strip block `type`:** `internet` (`host`, default `one.one.one.one`; `arrow_ms`, default 2; `timeout_s`, default 3),
  `load`, `volume`, `picture` (shows `icon`), `empty`. A tap runs the block's `action`. An unknown type makes the whole
  file invalid.
- **`swipe.action`:** one action for a swipe on the strip. **`lock_photo`:** shown across the N4 while the Mac is locked.
- **Old format still loads:** a file with no `decks` key is read as the N3 section — top-level `brightness`, `buttons`,
  `knobs` (the v1.0.0 layout). When `decks` is present, top-level `brightness`/`buttons`/`knobs` are ignored.

## Actions

| Action | Description |
|--------|-------------|
| `shell:<command>` | Execute shell command |
| `key:<shortcut>` | Simulate keyboard shortcut (e.g. `cmd+shift+4`) |
| `system_volume` | Adjust macOS system volume by ±step per tick |
| `system_mute_toggle` | Toggle system mute (daemon tracks state, syncs with actual) |
| `zr7_volume` | Adjust ZR7Player volume by ±step per tick (interface TBD) |
| `zr7_mute_toggle` | Toggle ZR7Player mute (interface TBD) |
| `display_brightness` | Adjust external monitor brightness by ±step per tick (DDC/CI via m1ddc) |
| `display_brightness_cycle` | Cycle brightness target: All → per-display → All (30 s auto-revert) |
| `none` | No action |

## External Monitor Brightness (DDC/CI)

macOS has no native support for controlling brightness on non-Apple external displays. The built-in brightness keys and Control Centre slider only work on the internal panel and Apple-branded monitors (e.g. Apple Studio Display, Pro Display XDR). Third-party displays — including high-end LG, Dell, and Samsung panels connected via USB-C or DisplayPort — are invisible to macOS brightness controls.

The industry-standard workaround is **DDC/CI** (Display Data Channel / Command Interface), a protocol where the OS sends commands over the display cable to adjust settings like brightness and contrast. On Apple Silicon Macs, [`m1ddc`](https://github.com/waydabber/m1ddc) is the most reliable DDC/CI CLI tool (works on M1–M4, all variants despite the name).

### How it works in this daemon

- Optional `displays` array in config maps friendly names to monitor AN Serials (from `m1ddc display list detailed`)
- At startup, the daemon resolves serials to current m1ddc display numbers (handles reboot shuffling)
- Knob rotation fires async `m1ddc set luminance` calls with debouncing (80 ms) to keep the knob responsive
- Knob press cycles the brightness target: All connected displays → each display individually → back to All
- After 30 seconds of inactivity, the target auto-reverts to All
- A floating HUD overlay (80 pt text) appears on all screens showing current brightness and target mode
- Brightness is read from hardware on first interaction after idle, then cached during active use to avoid flaky DDC/CI reads

### Known DDC/CI quirks

- LG monitors do **not** show their native OSD bar for DDC/CI brightness changes (only for physical button presses) — hence the custom HUD
- `m1ddc get luminance` can return stale values on some LG models — the daemon reads once then tracks state internally
- `m1ddc chg luminance` (relative change) is unreliable on some LG panels — the daemon uses absolute `set luminance` instead
- Display numbers from `m1ddc` can change across reboots — the daemon matches by serial number, not display number

### Dependency

`m1ddc` is the only external dependency. Install via `brew install m1ddc`. Without it, all other daemon features work — brightness actions simply log a warning.

## LCD Icons
- Optional `icon` field per LCD key in config; sent to the deck as JPEG via CRT BAT (header with length and wire
  slot), 1024-byte chunks, then STP
- N3: 85×85 JPEG, turned 90° + 180°, shifted −9 / +8 px to sit centred on the LCD. No icon = cleared/blank
- N4: keys 112×112 JPEG turned 180°, no offset; strip blocks 176×112 turned 180° (`picture` blocks show an icon).
  Slots: top-row keys 11–15, bottom-row keys 6–10, strip blocks 1–4. No icon = black

## Daemon Behaviour
- Runs as background process (launchd plist for auto-start)
- Connects to every supported deck on startup; each reconnects on USB replug while the others keep running
- Sends init sequence to each deck, then listens for events
- Sends CONNECT keepalive to every connected deck every 5 seconds
- On button press: executes mapped action (ignores release events for buttons)
- On knob rotate: applies ±step for each tick
- On knob press: executes the knob's press action
- Reloads the config on `SIGHUP` or the distributed notification `com.streamdeck.controller.reload`
  (`StreamDeckController --post-reload` posts it)
- `--config <path>` loads that file instead of searching (development); the same security checks apply
- Logs to stdout/file for debugging
- Graceful shutdown on SIGTERM/SIGINT

## Safety Constraints
- **HID isolation**: MUST only open the vendor interface (usage page 0xFFA0, usage 1) of the supported decks — N3 VID 0x5548 / PID 0x1001 and N4 VID 0x6602 / PID 0x1001. Never the decks' keyboard interfaces. Never enumerate, open, or interfere with any other HID device (keyboards, mice, trackpads, etc.)
- **No kernel driver manipulation**: MUST NOT unload, detach, or modify any macOS kernel drivers or kexts. The daemon operates purely in userspace via IOKit HID API
- **USB passivity**: MUST NOT send USB control transfers, reset devices, or alter USB configuration of any device other than the target deck
- **launchd safety**: The launchd plist MUST only manage this daemon's own process. No modification of other launchd jobs, plists, or system services. Use `LaunchAgents` (user-level), never `LaunchDaemons` (system-level)
- **Shell command sandboxing**: `shell:` actions run with the user's normal permissions. The daemon itself requires no elevated privileges (no sudo, no root)
- **Graceful failure**: If the device is not connected, the daemon waits quietly and retries. No error storms, no resource hogging, no interference with other USB devices

## Non-Goals (for now)
- No GUI
- No CLI config tool
- Hot-reload supported via SIGHUP (`killall -HUP StreamDeckController`) or `StreamDeckController --post-reload`
- No pages or scenes: one layout per deck model
- No Windows/Linux support
