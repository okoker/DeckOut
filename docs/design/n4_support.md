# MiraBox Stream Dock N4 — Support Design

**✅ BUILT 19/11/2026 → `docs/reference/n4.md`** (how it works now). This design stays as the record of why.
Approved by the owner 19/11/2026. Protocol verified on the unit 18–19/11/2026; mechanisms researched at source level
and builder-checked 19/11/2026.
Background: `docs/ideas/config_app_and_new_deck.md`. N3 protocol and macOS quirks: `docs/reference/device_quirks.md`.

## Intent
The user has a second, more capable deck: the MiraBox Stream Dock N4 (10 LCD keys in 2 rows of 5, a touch strip
showing 4 image blocks, 4 push-knobs). The daemon should drive it with every function the N3 has today, use the strip
as a live status bar, and show a photo on the deck while the Mac is locked. A simple native Mac app for configuring
the decks follows as a separate piece of work, after the N4 runs from the JSON config.

Users: the owner and a few friends. Signing comes later, once things settle; no first-run guide until then.

## Goals
1. **One daemon** drives every supported deck that is plugged in (N3 and N4), each with its own layout. Both decks
   may be connected at once and each works independently.
2. **Every current N3 function is available on the N4**: 6 app keys (Chrome, Docker, Avaz Player, Penkeep, TextEdit,
   Notes, with their app icons), 3 iTerm buttons (network popup, black-green, black-blue — they get the iTerm icon),
   3 knobs (system volume + mute, Avaz Player volume + mute, monitor brightness + cycle). Placement is decided later,
   in the app; any sensible placement is fine for now.
3. **Live strip**, left to right: 1 internet latency, 2 CPU + memory load, 3 empty, 4 system volume (details below).
4. **Lock photo**: while the Mac is locked, the N4's keys and strip together show one photo.
5. **Responsive**: a config change shows on the deck within about a second, with no flicker.
6. **Low impact on the Mac**: see the performance budget below.
7. **Ready to move into the app later** without a rewrite.

## Non-goals
- Pages / scenes (one layout per deck). Directional swipe (the firmware does not report direction).
- Replacing the deck's built-in start-up picture. The vendor Stream Dock app, its plugins, script-fed strip blocks.
- Signing, notarisation, App Store, first-run guide — later. N4 variants with other USB IDs (Ajazz AKP05 etc.).
- Text labels on keys (keys without their own icon get an app icon instead).
- The config app itself — separate design, after this ships.

## Anti-goals (a failure even if everything "works")
- Visible flicker or blanking when anything on the deck updates.
- Noticeable CPU or energy use; starting child processes every few seconds.
- Breaking existing N3-only configs (public v1.0.0 users) or the owner's current N3 setup.
- Deck keys running actions while the Mac is locked.
- An event from one deck firing another deck's action (their event codes overlap).
- Writing anything to the deck's permanent memory.

## Constraints
- macOS 15 on Apple Silicon; Swift 6.2 / Xcode 26; Swift Package Manager; no new third-party dependencies
  (`m1ddc` stays optional, as today).
- HID isolation (`REQUIREMENTS.md`): open only the vendor interface (usage page `0xFFA0`) of a supported VID + PID;
  never open a deck's keyboard interface or any other HID device.
- IOKit rules from `device_quirks.md` still hold: input only arrives while `CFRunLoopRun()` runs on the main thread;
  `IOHIDDeviceSetReport` takes data without the report-ID byte; nothing blocking on the main thread.
- Config security checks stay: regular file, owned by the user, not group/world-writable.
- The live daemon is a running system: installing or restarting it needs the owner's go each time. No new
  LaunchAgents, login items or other persistence without explicit approval.
- Public repo: no monitor serials or personal paths in committed files; `config.example.json` uses placeholders.

## Approaches considered
| Approach | Verdict |
|---|---|
| **Extend today's daemon**: a table of deck models, one connection per plugged-in deck, one shared action handler, built-in strip block types | **Chosen.** Smallest change that meets every goal; shared volume/brightness/mute state |
| One program per deck | Rejected (owner chose one daemon). Separate copies keep separate state, e.g. the brightness knob jumps back to a stale value |
| Script-fed strip blocks (draw whatever a script prints) | Rejected: starts programs every 5 s, against "low impact"; the built-in types cover the need |
| Daemon inside the app now | Deferred to the signing step; the code is structured so it moves without a rewrite |

Lock photo: **cut the photo into 14 pieces and send them like icons** (chosen — proven mechanism, nothing permanent)
vs. replacing the deck's start-up picture and making the deck show it (rejected — permanently overwrites the factory
picture in the deck's flash memory; untested on this unit).

## Design

### Code structure
- Split the package into a library target (all deck, config, action and rendering logic) and a thin executable
  (`main.swift`: config path, signals, run loop). A test target tests the library.
- Nothing depends on where the executable lives. The config stays at `~/.config/vsd/config.json`.
- Later, the app embeds the same library or ships the same executable inside its bundle.

### Deck models
A table of supported models. Each entry holds: name, VID / PID / usage page, the event map (byte-9 code → control
and kind), image specs per control (slot, size, rotation, offset), and the config keys it uses.
- **N3**: values exactly as today's code (85×85 JPEG, 90° + 180° turn, shiftX −9 / shiftY +8, current event codes).
- **N4**: values from the verified maps below; key images 112×112 turned 180° with **no offset** (owner's decision).
- Events are decoded with the map of the deck that sent them — never one shared table.

### Connections
- One HID manager matches all models. Each matched device gets its own connection object: start-up sequence,
  5 s keepalive, its own input buffer, its own layout.
- The HID callbacks carry one long-lived context (the manager); the device reference in the callback picks the
  connection. Connection objects come and go with plug / unplug without unsafe pointer lifetimes.
- Unplug / replug of either deck must work while the other stays connected.

### Config format
One file, one section per deck; shared settings stay at the top.
```json
{
  "displays": [ { "name": "Left", "serial": "…" } ],
  "decks": {
    "n3": { "brightness": 50, "buttons": { "lcd_1": { … } }, "knobs": { "big": { … } } },
    "n4": {
      "brightness": 50,
      "keys":  { "key_1": { "action": "shell:open -a Notes", "icon": "/System/Applications/Notes.app/…" } },
      "knobs": { "knob_1": { "rotate": { "action": "system_volume", "step": 5 },
                             "press":  { "action": "system_mute_toggle" } } },
      "strip": {
        "1": { "type": "internet", "host": "one.one.one.one", "arrow_ms": 2, "timeout_s": 3,
               "action": "shell:…open networkDetail2.sh in iTerm, POPUP-INFO profile…" },
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
- N4 key names: `key_1`–`key_5` top row left → right, `key_6`–`key_10` bottom row. Knobs `knob_1`–`knob_4` left →
  right. Strip blocks `1`–`4` left → right; a tap runs the block's `action`.
- Strip block types: `internet`, `load`, `volume`, `picture` (an `icon`), `empty`.
- **Old format still loads**: a file with no `decks` key is read as the N3 section (today's top-level
  `brightness` / `buttons` / `knobs`).
- Actions are unchanged: `shell:`, `key:`, `system_volume`, `system_mute_toggle`, `zr7_volume`, `zr7_mute_toggle`,
  `display_brightness`, `display_brightness_cycle`, `none`.
- The owner's live config is migrated to the new format by hand during the build (with the owner's go); the
  monitor serials stay only in the live file.

### Drawing
- All deck images are rendered in-process (CoreGraphics / CoreText) and sent as JPEG with `BAT`, then `STP`.
- **Redraw in place, never clear** after start-up: `BAT` + `STP` on its own updates a slot smoothly on the N4;
  clearing a slot first (`CLE <slot>`) blinks visibly (verified 19/11/2026).
- Reload: re-read the config, redraw every slot (a black image where nothing is set). No tracking of what changed.
- Live blocks: redraw the block whenever its value updates.

### Strip blocks
- **Internet** — every 5 s: look the host name up through the system resolver (also proves DNS works; mostly
  answered from the OS cache), send one ICMP echo, show the round-trip time in ms.
  - A big arrow sits behind the number: red ▲ when latency rose by at least `arrow_ms` (default 2) since the last
    reading, green ▼ when it fell by at least that much, no arrow otherwise.
  - No answer within `timeout_s` (default 3): the whole block turns red.
  - Mechanism: `getaddrinfo` for IPv4 only (system resolver, so it also proves DNS works), then one ICMP echo over
    an unprivileged `SOCK_DGRAM` / `IPPROTO_ICMP` socket kept open — the same socket Apple's own `ping` uses when
    not root. Both calls block, so they run off the main thread. Replies are matched on identifier + sequence
    (the kernel hands every ICMP reply to every ICMP socket). Time the lookup and the echo separately; the shown
    figure is the echo round trip. No child process. See Research notes.
- **Load** — every 5 s: CPU % and memory figure, each number coloured green → amber → red by its own value
  (independently). Memory uses macOS memory pressure (what Activity Monitor's memory graph shows), not "RAM used".
  - CPU %: `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas between readings, (user + system) / total.
  - Memory %: `100 − kern.memorystatus_level` (that sysctl is the percent of memory still available). Its colour
    follows macOS's own pressure level, `kern.memorystatus_vm_pressure_level`: 1 normal (green), 2 warning (amber),
    4 critical (red). CPU colour thresholds are the builder's call.
  - Both sysctls are readable without root but undocumented by Apple; if one fails, the block shows "–" for that
    figure instead of a wrong number.
- **Volume** — system output volume % and mute state, redrawn the moment either changes (knob or anywhere else),
  without polling. It needs a good-looking visual (e.g. a gauge); the builder proposes it on the real strip for the
  owner's approval.
  - Mechanism: CoreAudio property listeners — on the system object for `kAudioHardwarePropertyDefaultOutputDevice`,
    and on the current output device for `kAudioDevicePropertyVolumeScalar` and `kAudioDevicePropertyMute`
    (output scope, every element the device has: main, 1, 2). Any callback just re-reads volume and mute with the
    same functions the knob uses (`VolumeControl`), so the block always shows what the knob sets. On a default-device
    change, remove the listeners from the old device and add them to the new one. Callbacks arrive off the main
    thread; hop to the main thread before drawing.
- **Empty / picture** — drawn once.
- Measurements run only while a deck showing that block is connected and the Mac is unlocked, and never start
  child processes.

### Lock behaviour (all decks unless stated)
- Lock and unlock are detected from macOS's distributed notifications `com.apple.screenIsLocked` /
  `com.apple.screenIsUnlocked`, registered with `suspensionBehavior: .deliverImmediately` (the daemon creates
  `NSApplication` but is never "active", and AppKit may otherwise hold notifications back). They arrive on the main
  thread while `CFRunLoopRun()` runs. No entitlement or permission is needed.
- The state at daemon start: `CGSessionCopyCurrentDictionary()` key `CGSSessionScreenIsLocked`; a missing key or a
  NULL dictionary means unlocked.
- The notifications give the instant response; they are not trusted alone. The notification can fire when a screen
  saver merely starts, before the password delay has passed, and no second notification is known to follow when the
  Mac really locks. So the daemon re-reads `CGSSessionScreenIsLocked` **on every 5 s tick and before acting on any
  key, tap or swipe, whatever it currently believes**, and corrects its state (and the deck) when the two disagree.
  One cheap call per tick and per press. (Builder check, 19/11/2026.)
- Both mechanisms are undocumented by Apple ("implementation details rather than API") but used by Hammerspoon,
  Lunar and Stats today. Fast user switching is not covered (single-user Mac).
- **While locked**: keys, strip taps and swipes do nothing. Knobs keep working (e.g. turn music down while away),
  but only for the built-in actions — `system_volume`, `system_mute_toggle`, `zr7_volume`, `zr7_mute_toggle`,
  `display_brightness`, `display_brightness_cycle`. `shell:` and `key:` never run while locked, from any control
  (a `key:` action would type into the lock screen). Live measurements pause.
- **N4 with a `lock_photo`**: on lock, draw the photo across all 14 slots in place; on unlock, redraw the layout.
  - The keys and strip are windows onto one picture. Scale the photo to fill the deck's face (centre-crop), cut
    out each slot's rectangle at its position, turn it 180°, send it like an icon. The photo then reads as one
    picture behind the key frames.
  - Slot rectangles were measured on the N4 (19/11/2026) from a photo of a test grid. In key-image pixels: keys
    112×112 at 172 apart, rows 176 apart; strip blocks 176×112 at 208 apart, 352 below the top row; the face is
    800×464. The sibling AKP05E firmware's grid (x = 5 + 169·column, y = 15 + 174·row) was only the starting guess.
  - The photo file lives in `~/.config/vsd/` (the config points to it). macOS asks permission before a background
    program reads Desktop, Documents, Downloads or iCloud Drive, and for an unsigned daemon that permission is lost
    on every rebuild (the same trap as Accessibility in `device_quirks.md`). The app will later copy a chosen photo
    there.

### Swipe
One assignable action (`swipe.action`, default `none`). Only code `0x39` counts as a swipe; `0x38` (touch outside the
blocks) is logged and ignored — counting it would also fire on taps between blocks. Builder's call; revisit if
swipes feel unreliable.

### Reload signal and responsiveness
- Today: `SIGHUP`. Added: a distributed notification with a fixed name (e.g.
  `com.streamdeck.controller.reload`) that the app will post after saving. Either one re-reads the config through
  the same security checks and redraws. Any local process could post it, but it only triggers a re-read of the
  same checked file — the same power `SIGHUP` already gives same-user processes.
- Target: a saved change shows on the deck within ~1 s.

### Performance budget
- Measure the current daemon first (CPU % and memory over ~10 min, N3 only) as the baseline.
- New daemon with only the N3 connected: no worse than the baseline.
- With the N4 and the live strip running: average CPU under 0.5 % of one core, memory within ~10 MB of the
  baseline, no child processes started by the live blocks.

### App sketch (only to check the config covers what the app will edit)
```
┌ Decks: [N4 ●connected] [N3 ●connected] ───────────── Brightness ━━━●━━  Lock photo [choose…] ┐
│ ┌──┐┌──┐┌──┐┌──┐┌──┐        │ Selected: key 3                                                │
│ └──┘└──┘└──┘└──┘└──┘        │ Action:  [Open app ▾]  Notes                                   │
│ ┌──┐┌──┐┌──┐┌──┐┌──┐        │ Icon:    [drop an app or image]                                │
│ └──┘└──┘└──┘└──┘└──┘        │ (strip block: Type [Internet ▾]  host  arrow ms  timeout)      │
│ [ 1 ][ 2 ][ 3 ][ 4 ]  strip  │ (knob: Rotate [System volume ▾] step 5 / Press [Mute ▾])       │
│  ◯    ◯    ◯    ◯    knobs   │                                         changes apply at once  │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```
Every field shown maps to a config field above.

### Testing
- **Automated** (new test target): per-model event decoding including the overlapping codes; config parsing of the
  old and new formats; lock-photo slot cutting; arrow and colour rules.
- **On the device** (owner + builder): every N4 control, both decks connected at once, unplug / replug,
  lock / unlock, reload without flicker, strip visuals, N4 brightness range, the performance budget.
- Device checks also cover Mac sleep / wake with each deck connected. The N4 now runs from the UGREEN dock's front
  USB-C port (20 W, 10 Gbps). On 19/11/2026 that port first gave it no power at all, and only did after a phone
  had been plugged in and out. Check that the deck powers up again after Mac sleep / wake and after the dock loses
  power. If it doesn't, it's a dock-port quirk the daemon can't fix; the dock's back Thunderbolt port worked first
  time.
- **While developing**:
  - Development builds take a `--config <path>` option and run against a test copy of the config, never the live
    file. The installed daemon can't read the new format, so the live file changes only at install.
  - N4-only sessions: the owner unplugs the N3, so the installed daemon and the development build never both react
    to the same press.
  - N3 and both-decks checks happen **before** install: the installed daemon is stopped for that session (the
    owner's go each time) and restarted afterwards.
  - Install = new binary + hand-migrated live config in one step, with the owner's go (expect the one-off relaunch
    from KI-008). The previous binary and previous config are kept side by side, so rolling back is restoring both.
- Keep today's fallback of a `config.json` next to the executable, so v1.0.0 setups keep working.

### Docs to update when built
`REQUIREMENTS.md` (multi-deck non-goal flips, N4 device, config structure, lock behaviour), a `reference/` doc for
the N4 and the new config, `README.md`, `config.example.json`, `TESTS.md`, `PROGRESS.md`; this file gets a
"✅ BUILT" marker pointing at the reference doc.

### Left to the builder
Exact visuals for the strip blocks (shown on the device for approval), colour thresholds, timer layout, file and type
names, the notification name, log wording, how to place the N3 functions on the N4 for now. Also: what the N4's
`brightness` value maps to once its range is measured; staying on Swift 5 language mode and the macOS 13 minimum;
which thread sends images and a cap on how often a slot is redrawn; what the N4 shows when locked without a
`lock_photo` (its normal layout, inert, live blocks paused, is the expected default).

## Verified facts

### Device identity (read from the unit)
- USB: VID `0x6602`, PID `0x1001`, product string "HOTSPOTEKUSB HID DEMO" (same string as the N3).
- Firmware, via feature report `0x01`: `V3.Mbox_N4.02.014` — protocol v3, like the N3.
- USB layout identical to the N3: interface 0 = vendor HID (usage page `0xFFA0`, usage 1, 512-byte input, 1024-byte
  output; report descriptor byte-identical to the N3's); interface 1 = 8-byte boot keyboard. No bulk endpoint —
  images go over the vendor HID interface, as on the N3.

### Protocol — same as the N3
Verified on the unit: start-up `DIS` → `LIG` → `STP` → `CLE`; images via `BAT` header + JPEG in 1024-byte chunks +
`STP`; `CONNECT` keepalive every 5 s; input frames start `ACK\0\0OK\0\0`, event code at byte 9, state at byte 10
(no report-ID byte on macOS).

Brightness (verified 19/11/2026): the full `LIG` range 0–100 works on the N4. Each step up to 100 is visibly
brighter, and 0 is dim, not off. The sibling AKP05E stock firmware caps `LIG` at 60; the N4 does not.

Not tested on the unit:
- Watchdog. On the AKP05E, `DIS` starts a 20 s watchdog and the dock resets itself if the host sends nothing for
  ~15 s. The 5 s keepalive covers it either way.

### Input map (verified 18/11/2026)

| Control | Code (byte 9) | State (byte 10) |
|---|---|---|
| Top-row keys, left → right | `0x01`–`0x05` | 1 press, 0 release |
| Bottom-row keys, left → right | `0x06`–`0x0A` | 1 press, 0 release |
| Strip block 1–4 tap, left → right | `0x40`–`0x43` | one frame, state 0 |
| Strip swipe (either direction) | `0x39` | one frame, state 0 |
| Strip touch outside the 4 blocks (meaning per AKP05E firmware) | `0x38` | one frame, state 0 |
| Knob 1 (leftmost): clockwise / anticlockwise / press | `0xA1` / `0xA0` / `0x37` | rotate 0; press 1 only |
| Knob 2 | `0x51` / `0x50` / `0x35` | same |
| Knob 3 | `0x91` / `0x90` / `0x33` | same |
| Knob 4 | `0x71` / `0x70` / `0x36` | same |

- Codes overlap with the N3 with different meanings: `0x01`–`0x06`, `0x50`/`0x51` (N3 big knob = N4 knob 2),
  `0x90`/`0x91`, `0x33`, `0x35`.
- No release for knob presses or strip taps, so "hold" cannot be an action on them. Keys do send release.
- Swipes carry no direction: left→right and right→left both send `0x39`; every byte after the state byte is zero.
  The AKP05E stock firmware behaves the same.
- A swipe sometimes arrives as `0x38`. Counts per round: with the transit film on, 6 of 6 swipes came as `0x39`;
  without it, a mixed-direction round of 6 gave 1 × `0x39`, 4 × `0x38` and 1 missed; 10 direction-separated swipes
  gave 9 × `0x39` and 1 × `0x38`. Most likely those swipes began outside the blocks (at the strip's edge).
- Taps worked through the transit film.

### Display map (verified 18–19/11/2026)

| Area | Wire slot (`BAT` byte) | Image |
|---|---|---|
| Top-row keys, left → right | 11–15 | 112×112 JPEG, rotated 180° |
| Bottom-row keys, left → right | 6–10 | 112×112 JPEG, rotated 180° |
| Strip blocks 1–4, left → right (one above each knob) | 1–4 | 176×112 JPEG, rotated 180° |

- Slot 5 is unused. The strip is four separate images, not one canvas.
- Key press codes and image slots differ: top-row key `0x01` shows slot 11, bottom-row key `0x06` shows slot 6.
- Updating one slot with `BAT` + `STP` alone works and looks smooth; `CLE <slot>` first blinks the slot visibly
  (138 updates, 19/11/2026).
- Positioning: test labels showed horizontally centred and a couple of pixels high. The test label sat ~6 px below
  the canvas centre (centred under a 12 px bar), so a canvas-centred icon will sit higher. No correction for now
  (owner, 18/11/2026): the offset may be deliberate, for viewing a reclined unit at an angle.
- Not used: the deck's start-up picture (`LOG`, 800×480, stored in the deck).
- **`BAT` images live in RAM only — no flash wear from the live strip** (~35,000 slot redraws a day). Evidence from
  the AKP05E firmware rebuilt from the stock image: `BAT` → `display_key_image()`, a frame-buffer draw
  (`threads.c` L267-268); the only storage write in the firmware is `LOG` → `logo_write_file()` (`threads.c`
  L256-257, `storage.c` L16-33). The N4's own firmware was not inspected; same command set, same family. Without a
  host the deck always shows its start-up picture, so a replug test cannot tell either way.

### Security notes
- The boot-keyboard interface exists on the N3 too. AKP05E firmware types only when the host sends `CRT KEY`; the
  daemon never sends it. Not verified for the N4 firmware.
- Vendor Stream Dock installer, inspected without installing: one Qt app (~1.6 GB), no install scripts, no
  LaunchAgents/daemons/drivers; its Info.plist asks for camera, microphone, contacts, calendar, location, photos and
  AppleScript on behalf of its plugins. Not used.

### How it was verified
A throwaway Swift/IOKit probe (not in the repo) opened only the N4's vendor interface, ran the start-up, drew
numbered test images on slots 1–4 and 6–15, read the firmware string, and logged every raw input report while the
owner worked each control. Rounds on 18/11/2026: with the strip film, without it, swipes one direction at a time.
19/11/2026: a 2 s update loop alternating `BAT`+`STP` with `CLE`+`BAT`+`STP`, watched by the owner.

## Research notes

### Unprivileged ICMP (19/11/2026)
- macOS allows ICMP echo without root over `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)`: Apple's `ping` does exactly
  this when not root (network_cmds-741.100.2 `ping.tproj/ping.c` L314-315 `if (getuid()) s = socket(AF_INET,
  SOCK_DGRAM, IPPROTO_ICMP);`); Apple's SimplePing sample (`SimplePing.m` L597) and Go's `x/net/icmp`
  (`listen_posix.go` L69) do the same. xnu `ip_icmp.c` L1130: "Like rip_attach but without root privilege
  enforcement". Working from a launchd agent is inferred, not sourced.
- The kernel does not rewrite the echo identifier and delivers each ICMP reply to every ICMP socket, so match on
  identifier + sequence (SimplePing L400). IPv4 replies include the IP header unless `IP_STRIPHDR` is set (Go sets
  it on darwin, `listen_posix.go` L73-74); SimplePing skips the header itself.
- `getaddrinfo` is answered by mDNSResponder (its cache); not cached in-process. Asking for both A and AAAA can wait
  ≥ 50 ms for the slower answer (Libinfo `mdns_module.c` L1823-1825), hence IPv4 only. CFHost is deprecated.
- Local-network privacy (TN3179) does not mention ICMP; one.one.one.one is not a local address anyway.

### CPU and memory pressure (19/11/2026)
- exelban/stats @ `8bf536fe`, `Modules/CPU/readers.swift` L105-125, L170: `host_statistics(…HOST_CPU_LOAD_INFO…)`,
  deltas of user / system / idle / nice ticks, usage = (system + user) / total. MenuMeters @ `3b8d75fd` does the
  same per core with `host_processor_info` and averages.
- stats `Modules/RAM/readers.swift` L63-77: `kern.memorystatus_vm_pressure_level` (2 → warning, 4 → critical,
  else normal) and `pressurePercentage = 100 - Int(memoryLevel)` from `kern.memorystatus_level`.
- xnu `osfmk/vm/vm_pageout.c` L4738: `memorystatus_level = (available_memory * 100) / total_pages` — percent
  available. The sysctl handler checks privilege only on non-macOS targets.

### CoreAudio change listeners (19/11/2026)
- FelixKratz/SketchyBar @ `a18fc948`, `src/volume.c` L10-33, L93-147: listeners on the default-output-device
  property (global scope) and on VolumeScalar / Mute (output scope, element main and 1); on device change it removes
  the four listeners from the old device, adds them to the new one, and redraws once.
- Hammerspoon @ `23e387e2`, `extensions/audiodevice/libaudiodevice.m` L1722-1733: registers with wildcard scope and
  element; callbacks hop to the main queue (L88).
- Our `VolumeControl.getVolume` already reads element main, falling back to element 1 — the listener only triggers
  that read.

### Screen-lock detection (19/11/2026)
- Hammerspoon @ `23e387e2`, `extensions/caffeinate/libcaffeinate_watcher.m` L248-255: observes
  `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` on `NSDistributedNotificationCenter`.
- Lunar @ `06950e25`, `Lunar/AppDelegate.swift` L1600-1603: the same two names via
  `DistributedNotificationCenter.default().publisher(for:)`.
- Startup state: Stats @ `8bf536fe`, `Kit/helpers.swift` L2490-2491: `CGSessionCopyCurrentDictionary()` →
  `dict["CGSSessionScreenIsLocked"] as? Bool ?? false`. xnu `IOKitKeysPrivate.h` L50 defines the key (private).
- Apple docs: distributed notifications are delivered to the main thread of a task running its run loop in a common
  mode; `NSApplication` suspends delivery while the app is inactive — hence `.deliverImmediately` (also used by the
  LoupixDeck stream-deck app, PR #636).
- Known gaps: openradar 26264008 — fires when a screen saver or display sleep begins, even before the password delay
  passes; no evidence it fires for fast user switching. No reports of breakage on macOS 14/15 for normal processes.

## Sources
- Vendor SDK, MiraboxSpace/StreamDock-Device-SDK @ `fc124cb5`:
  - `CPP-SDK/src/HotspotDevice/StreamDockN4/streamdockN4.cpp` L4-8 (VID/PID), L39-74 (report sizes, image sizes,
    slots, event map) —
    https://github.com/MiraboxSpace/StreamDock-Device-SDK/blob/fc124cb5bc8fe0cd6c72d3f2af80588adc7dcffb/CPP-SDK/src/HotspotDevice/StreamDockN4/streamdockN4.cpp
  - `Python-SDK/src/StreamDock/Devices/StreamDockN4.py` (image formats, input decoding).
- 4ndv/mirajazz @ `af316240`, `src/device.rs` — `BAT` header, `LIG`, `CONNECT`, firmware feature report:
  https://github.com/4ndv/mirajazz/blob/af316240cdad56cb9cb9505cee5f40e80e9b7917/src/device.rs
- sejtam-dev/AKP05E-Open-Firmware @ `89e00af6` (rebuilt AKP05E firmware, not this PID):
  - `docs/host-protocol.md` — watchdog, events, `CLE` / `STP` semantics, differences from stock firmware.
  - `firmware/app/threads.c` L99-103 — `LIG` capped at 60.
  - `firmware/app/display.c` L41-65 — 800×480 panel, key tile grid.
  - `firmware/app/threads.c` L256-268, `firmware/app/storage.c` L16-33 — `BAT` draws to RAM; only `LOG` writes
    storage.
  - https://github.com/sejtam-dev/AKP05E-Open-Firmware/blob/89e00af6fa2987e41b11b58d596a92d9ee6b55fd/docs/host-protocol.md
