# Config App — Design

Draft 19/11/2026. Decisions by the owner on 19/11/2026 unless marked **(CL call)**: those are Claude's calls,
stated to the owner and not objected to, or made in this write-up. Idea note: `docs/ideas/config_app_and_new_deck.md`.
Mockups: `docs/assets/config_app_main_window.html`, `docs/assets/config_app_lock_photo.html`.

## Intent

A Mac app for setting up the TreasLin N3 and MiraBox N4 decks, so nobody edits `~/.config/vsd/config.json` by hand.
It's for friends and family first, and for anyone else who finds the open-source repo. The app becomes the way
to configure a deck. Hand edits still load, but the app overwrites them on save (owner: fine).

It must look and feel like a polished, simple Mac app, nothing ad hoc. You edit only a deck that's plugged in, and
every change shows on the real deck at once, so you see that it worked and that it's what you expected.

## Goals
- Edit every control on both decks: N3 `lcd_1`–`lcd_6`, `btn_1`–`btn_3`, knobs `big`, `small_1`, `small_2`; N4
  `key_1`–`key_10`, strip blocks `1`–`4`, knobs `knob_1`–`knob_4`.
- Set up the live strip blocks (internet latency, CPU / memory, volume, picture, empty) and their settings.
- Presets per deck, switched from a pull-down in the app.
- Per-deck brightness, 0–100, default 75.
- The N4 lock photo: choose, move, zoom, with a preview of the 14 screens.
- Friendly actions: Open App, Open Website (any full URL, path included), Open File or Folder, Keyboard Shortcut
  (recorded by pressing it), Run a Shortcut (Apple's Shortcuts app), Volume / Mute, Monitor Brightness, Play / Pause,
  Next Track, Previous Track, Run Script, and Run Command (advanced).
- Icons: the app's own icon, your image, text on a colour, or a built-in icon library.
- A Test button that runs an action exactly as a key press would and shows its output or error.
- Install by dragging the app into Applications. The background part starts at login. No Terminal, ever.

## Non-goals (this version)
- Editing a deck that isn't plugged in.
- Sharing setups: export, import.
- Switching presets by swiping the strip. It comes later, so presets are stored where the background part can use
  them (see Config).
- Knobs in presets. They belong to the deck.
- Other deck models (keep it possible: per-model drawing + map), two decks of the same model, Intel Macs, languages
  other than English, the App Store, a menu bar icon, live blocks driven by your own scripts.

## Anti-goals (a failure even if it works)
- Anything that looks ad hoc or like a developer tool.
- A second modal layer to reach presets.
- The app touching any USB device, or the background part touching anything beyond the decks' vendor interface.
- A key that works in Test but not when pressed (different environment).
- Key presses slowed by the app.

## Constraints
- macOS 15 (Sequoia) or later, Apple Silicon only (bundled `m1ddc` is Apple-Silicon-only; Intel can't be tested
  here). There's no macOS 14 Mac to test on (owner), and only versions we can test are claimed. macOS 15 runs on every Mac that
  runs 14 except the 2018–2019 MacBook Air.
- Swift + SwiftUI, in this Swift package. The app shares `DeckCore` with the background part.
- Not the App Store: the sandbox blocks `shell:`, `m1ddc` and automating other apps. Developer ID signed and
  notarised for release. **Every signing or notarising run needs the owner's go**; the identity is never picked
  automatically.
- **Signed with the owner's existing Developer ID certificate** (owner, 19/11/2026, told that the certificate's name
  is public in every signature). Only the signature carries that name: README, LICENSE and the About box stay
  "Koker", and this repo never names the certificate. **(CL call)** The identity name lives in a gitignored local
  file the Makefile reads, so the repo builds for anyone with their own certificate. **(CL call)**
  Before the first signed build the owner checks in Keychain Access which authority issued the certificate: one from
  the original Developer ID Sub-CA can't make new signatures after 01/02/2027, so make its replacement from G2.
- HID safety rules in `REQUIREMENTS.md` stand unchanged. The app never opens USB devices; it asks the background part.
- The config stays at `~/.config/vsd/config.json`, and the load-time checks stay: not a symlink, owned by the user,
  not writable by group or others. The app writes it atomically (temp file + rename in the same folder), mode 0600.
- BL-001 (half-second main-thread stall per reload, no coalescing) lands before the app, which reloads on every change.
- Public repo: the live config holds monitor serials and must never be copied into it. No signing identity names in
  the repo.
- **Name: DeckOut** (owner, 19/11/2026). It's set from phase 1:
  the bundle id, agent label, Mach service, log folder and helper name all derive from it, and macOS files saved
  permissions and Login Items under the bundle id, so a later rename leaves stale entries. "Stream Deck" is Elgato's
  trademark: don't use it. FreeDeck is taken by an open-source DIY deck with its own configurator.
  - Bundle id `io.github.okoker.deckout` (owner, 19/11/2026): it ties to the public GitHub name, needs no domain,
    and stays valid if the signer ever changes (a bundle id can't change without losing permissions).
  - The helper is renamed from `StreamDeckController` (it shows in Activity Monitor and the Accessibility list);
    the builder picks the spelling, e.g. `DeckOutAgent`.
  - The GitHub repo is `okoker/DeckOut`, renamed from `StreamDeckController` on 19/11/2026 (owner); GitHub
    redirects the old address. The README stays as it is until the app ships.
  - Web search only (19/11/2026): no Mac app, repo or deck product called DeckOut; "DeckedOut" is an unrelated
    trading-card app on the App Store. No trademark-register search was done.

## Approaches considered
1. **One app with the background part inside it (chosen).** The bundle holds the GUI and today's daemon as a separate
   helper program, registered to start at login with `SMAppService.agent`. They talk over XPC. Closing or crashing the
   window never touches the decks; today's daemon carries over almost unchanged. Prior art: Karabiner-Elements registers
   its per-user agents from inside the app (`src/apps/ServiceManager-Non-Privileged-Agents/src/main.swift:16-27`,
   job plist pointing into `/Applications/Karabiner-Elements.app`); Copilot for Xcode does the same when running from
   `/Applications` and talks to its agent over a Mach service (`Core/Sources/LaunchAgentManager/LaunchAgentManager.swift:38-46, 77-80, 96-100`).
2. **One program for both.** Rejected: a bug in an editing screen takes the decks down; the deck code has no teardown
   (`Daemon` / `DeckManager`, IOKit callbacks with unretained pointers); a slow screen delays key presses.
3. **Today's hand-written LaunchAgent plus an editor app.** Rejected: Login Items shows a bare "unidentified
   developer" program; binning the app leaves a login job pointing at a missing file; Apple is moving away from it.

## Architecture

### Bundle
- `/Applications/<Name>.app`: the GUI is the main executable. The deck controller (today's `StreamDeckController`)
  is a helper executable inside the bundle, plus `Contents/Library/LaunchAgents/<agent-id>.plist` registered with
  `SMAppService.agent(plistName:)`.
- Agent plist: `Label`, the helper's path, `KeepAlive`, `MachServices` (the XPC endpoint),
  `AssociatedBundleIdentifiers` = the app's id (one Login Items entry with the app's name and icon). Whether to use
  `BundleProgram` (bundle-relative) or an absolute `/Applications/...` path like Karabiner: builder verifies.
- The app works only from `/Applications/<Name>.app`; anywhere else it shows "Move <Name> to Applications" and does
  nothing else (both reference apps assume `/Applications`; also catches App Translocation).
- Logs: the helper logs to a file under `~/Library/Logs/<Name>/` (builder picks), as today.

### XPC between the app and the background part
- The helper vends one `NSXPCConnection` Mach service. Calls (names are the builder's):
  - `status` → running, version, connected decks (model + live state), shell-environment result (resolved / fell back
    / timed out).
  - deck connect / disconnect pushed to the app as they happen.
  - `reload` → re-read the config; reply says whether it loaded or why not.
  - `test(action)` → run one action exactly as a press would; reply with stdout, stderr, exit status, or the error.
  - `showLockPhoto(on, framing)` → put the lock photo on the N4 while the app's photo mode is open (today's
    `--show-lock-photo`, made switchable at run time), and redraw as the framing changes.
- Once signed: each side checks the other's code signature (`NSXPCConnection.setCodeSigningRequirement`, macOS 13+):
  same team, expected identifier. Each side reads its own team id from its signature at run time, so no team id
  lives in the repo. **(CL call)** Before signing, any process running as the user can connect; that gives it nothing
  it can't already do as the user.
- `--post-reload` and the `com.streamdeck.controller.reload` notification stay for scripts and back-compat.
- The app's "running" indicator comes from `status`, never from `SMAppService.status` (it has been
  seen reporting "enabled" while off, and the reverse, on macOS 26).

### First run and removal
- First open from Applications: register the agent; macOS shows its "background item added" notice. The app waits for
  `status` and shows the result.
- If the v1.0.0 hand-installed agent exists (`~/Library/LaunchAgents/com.streamdeck.controller.plist`, the README
  install), the app offers to remove it: two controllers would both act on every press. **(CL call)**
- An existing config loads as is (old and current formats), then gets the app's format on the first save. Before that
  first save, the app copies the file aside, for example `config.json.before-app`. The installed daemon can't read
  the preset format: it requires N3 `buttons` (`Config.swift:64-67`) and reads a missing N4 `keys` / `strip` as empty
  (`Config.swift:88-90`), so rolling back needs the old file. **(CL call)**
- **The background part never exits for want of a config.** Today it exits when there's no config
  (`main.swift:40-46`) or it doesn't load at start (`main.swift:136-141`). Run with `KeepAlive`, that crash-loops for
  every new user. Instead it starts with no decks set up, keeps the decks blank, and reports the problem through
  `status`. **(CL call, from review)**
- Removal: an app menu item unregisters the agent; then the person bins the app. Builder: check and document what
  happens when the app is binned while registered.

### Updates
- The person downloads the new version from the repo's GitHub Releases and drags it over the old one (owner). No
  in-app updater: Sparkle would add a third-party library, a hosted feed and a second signing key.
- The app compares its version with the background part's (from `status`) and restarts the agent on a mismatch, so
  the new helper runs without a logout.
- A download from GitHub is quarantined, so every release is notarised (owner's go each time), or macOS refuses to
  open it.

## Config changes
The app writes only keys it knows. Unknown keys are dropped on save (owner: fine). Encoding must round-trip: decode →
encode → decode gives the same config (today's types are mostly `Decodable` only).

### Presets
Per deck, stored in the config so the background part knows them all (swiping later needs no migration). The JSON
key names are the builder's; the shape is decided:
```json
"n4": {
  "brightness": 75,
  "knobs": { "...": "..." },
  "swipe": { "action": "none" },
  "lock_photo": { "...": "..." },
  "presets": [
    { "name": "Work",  "keys": { "...": "..." }, "strip": { "...": "..." } },
    { "name": "Music", "keys": { "...": "..." }, "strip": { "...": "..." } }
  ],
  "active_preset": "Work"
}
```
- N4 preset = `keys` + `strip`. N3 preset = `buttons` (`lcd_1`–`lcd_6`, `btn_1`–`btn_3`). Knobs, brightness, swipe
  and the lock photo stay at deck level.
- A deck section without `presets` (today's files) reads as one preset named "Default".
- `active_preset` is the name; the app keeps names unique and rewrites both in one save. A missing name falls back to
  the first preset, with a log line.
- Picking a preset in the app makes it live on the deck (no separate "editing" preset). **(CL call)**

### Lock photo framing
`lock_photo` becomes `{ "path", "zoom", "offset_x", "offset_y" }`: zoom ≥ 1 on top of today's aspect-fill of the
800×464 canvas, offsets as a fraction of the canvas. The photo always covers the canvas (clamp the offset); no black
edges. The old string form still loads (zoom 1, centred). `LockPhoto` applies it when cutting the 14 slots.

### Actions
New kinds get their own prefixes so the app can show back what was picked. Builder picks the spellings:
- `app:<path to .app>` (open the app; its icon fills the key automatically), `url:<URL>` (default browser; any full
  URL including path and query), `open:<path>` (file or folder), `script:<path>`, `shortcut:<name>` (Apple
  Shortcuts). `key:`, `shell:` (Run Command), the built-ins and `none` stay.
- **Media (owner: wanted):** Play / Pause, Next Track, Previous Track, sent as the Mac's own media keys, so they
  control whatever is playing. Posting them needs Accessibility, like `key:` (`docs/reference/device_quirks.md`,
  "Volume Control"). Offered on keys, knob presses, strip taps and the swipe, not on knob turns: one click per
  report would skip several tracks on a quick turn. **(CL call)**
- Arguments go to `Process` as an argument array, never pasted into a shell string.
- Lock rules: every new kind is blocked while locked, like `shell:` and `key:` (`LockPolicy.allows`,
  `ActionResolver.swift:59`).
- **Which actions each control offers (CL call, from the code):**
  - Today a key press carries no step (`ActionResolver.swift:29`), and `system_volume` / `display_brightness` use
    `step ?? 0` (`ActionDispatcher.swift:144-147`), so a volume action on a key does nothing. Keys therefore get
    "Volume up / down" and "Monitor brightness up / down", each with a step. That's a new field on key actions.
  - A knob turn passes its step to every action (`ActionResolver.swift:31`), and `shell:` / `key:` ignore it, so
    those would fire the same way in both directions. Knob turns offer only stepped actions: volume and monitor
    brightness. Knob presses offer the same list as keys.
  - ZR7 is off the menus (owner). A control already set to a ZR7 action shows it read-only, with a way to replace it.
- **Scripts run where they are.** The app warns when you pick one: moving or renaming it breaks the key. Each time
  the app opens it checks every `script:` and `open:` path and marks keys whose file is gone. Picking a script in
  Desktop, Documents, Downloads or iCloud Drive warns that macOS will ask permission the first time it runs.
  Builder: a script that isn't executable — offer to fix, or run it via its `#!` line.
- **Environment:** `shell:` and `script:` run with the user's own shell environment, resolved once (the VS Code
  approach, `src/vs/platform/shell/node/shellEnv.ts:70, 109-155`). The helper starts the user's login shell as
  login + interactive, captures the environment between markers, and caches it. It re-resolves at start, on
  reloads that don't come from the app (SIGHUP, `--post-reload`), and from a Refresh button in Settings. It doesn't
  re-resolve on the app's own saves: those come with every edit and slider drag, and each would run the person's
  `.zshrc`. **(CL call, changed from "on every save" after review.)** Ten-second cutoff, then a fallback PATH that adds
  `/opt/homebrew/bin` and `/usr/local/bin`; `status` reports which happened and the app shows it. This replaces the
  `zsh -lc` workaround (the arp-scan problem).

### Icons
- Keep `icon` as a path the background part draws.
- App icons: the `.app`'s own icon, by path (as today).
- Chosen images, text-on-colour tiles and library symbols: the app copies or renders them into
  `~/.config/vsd/icons/` and points `icon` there. A small extra field records how a generated tile was made (text,
  colours, symbol) so the app can edit it again; the background part ignores it. **(CL call)**
- Chosen lock photos are copied into `~/.config/vsd/` (background reads of Desktop / Downloads trigger permission
  prompts).
- Library: a permissively licensed open icon set shipped with the app, its licence in the app's licences screen.
  Which set: owner to confirm (see open questions).

### Monitors
`m1ddc` ships inside the app. It's MIT-licensed according to GitHub: read the LICENSE file before shipping and include
it. The app lists monitors from `m1ddc display list detailed` and lets the person name them, writing `displays`. No
one types a serial.

## The app

### Main window (mockup A, approved)
```
┌ ● ● ●  [▣ N4]  [▣ N3 (grey)]   Preset [Work ⌃⌄]          ☀ ━━━━●━ 75   [Lock Photo…] ┐
│                                            │ KEY 3 · TOP ROW                          │
│   ┌─────── N4, real proportions ───────┐   │ Action  [Open App      ⌃⌄]               │
│   │ ▢ ▢ (▢) ▢ ▢     ← red ring = selected│   │ App     ▣ Notes          [Choose…]       │
│   │ ▢ ▢  ▢  ▢ ▢                         │   │ Icon    [App|Image|Text|Library]         │
│   │ ┌────┬────┬────┬────┐ ← one panel   │   │         ▣ preview as the deck shows it   │
│   │ └────┴────┴────┴────┘   thin lines  │   │ ───────────────────────────────          │
│   │   ◯     ◯     ◯     ◯               │   │ [▶ Test]  runs it as a key press would   │
│   └─────────────────────────────────────┘   │                              Clear Key   │
├────────────────────────────────────────────┴──────────────────────────────────────────┤
│ ● Deck controller running        Changes apply at once · ⌘Z undoes                      │
└────────────────────────────────────────────────────────────────────────────────────────┘
```
- Window about 946×544; the deck drawn at the mockup's size. Light and dark follow macOS.
- **Deck buttons:** one real button per model, with a small drawing of that deck in colour, as in the mockup: N3 six
  screens, the big knob, three buttons and two small knobs; N4 ten screens, the strip and four knobs (owner, after
  comparing the vendor app's simple deck icons). Not plugged in: greyed out. Plugged
  in while the app is open: turns to colour (no badge, no dot). The deck on screen looks pressed in.
- **On launch:** one deck plugged in → open it. Both → a "pick a deck" screen. None → "Plug in your deck".
  Unplugging the deck on screen switches to the other, or to "Plug in your deck". **(CL call)**
- **Deck drawing:** real proportions. N4 screens from the measured layout (keys 112 px at 172 px pitch, rows 176
  apart, strip blocks 176×112 at 208 pitch, 352 below the top row; `docs/reference/n4.md`); its knobs and body edge
  drawn by eye. The N3's notes hold its image size and offsets, not where its screens, buttons and knobs sit, so its
  drawing is laid out from `docs/assets/streamdeck.jpg`, straightened in software. Near enough is fine: nothing is
  cut to the N3 drawing. **(CL call)** It shows exactly what the deck shows, rendered with DeckCore's own
  code (make `ImageLoader`, `StripRenderer`, `LockPhoto.canvas` / `n4Rects` public rather than copying numbers).
  Live strip readings update in the drawing.
- **The touch strip** is one outlined panel with thin lines between its four areas (owner picked option 1).
- **Selection:** a red ring on the selected key, strip area (ring inside the panel) or knob.
- **Preset pull-down:** presets with a check on the live one, then New Preset, Duplicate, Rename, then Delete. New and
  Rename edit the name in place in the toolbar, with no dialog. Delete asks nothing; ⌘Z restores.
- **Brightness** slider in the toolbar; **Lock Photo…** only for the N4.
- **Applying:** every change writes the config and asks for a reload at once. Text fields apply when you finish
  (Return or leaving the field). ⌘Z / ⇧⌘Z undo and redo within the session.
- **Status line:** "Deck controller running" (from `status`), "Changes apply at once · ⌘Z undoes", and any problem
  the background part reports (not running, shell environment fell back).

### Lock photo mode (mockup approved)
- Lock Photo… switches the window into photo mode. There's no separate window or sheet.
- The deck drawing shows the photo across the 14 screens exactly as cut. "Show hidden parts" shows faintly what falls
  behind the frames.
- Drag on the deck to move the photo, and scroll, pinch or use the slider to zoom. Reset centres it again.
- "Show on the deck" (on by default) puts it on the real N4 while editing, via `showLockPhoto`.
- The preset menu is dimmed while in photo mode. **Done** returns to the keys. **Remove Photo** clears it.

### Not mocked yet: mock on the real window before building, owner approves
- The panel for every action kind, the knob editor (rotate action + step, press action) and the strip-block editor
  (type + settings + tap action).
- The script-moved warning and the missing-file mark on a key.
- The keyboard-shortcut recorder and the icon library picker.
- The "Pick a deck", "Plug in your deck" and first-run screens.
- The "Move to Applications" screen.
- A standard Settings window (⌘,) for monitors and their names, the background part's state, and licences.
  **(CL call)**

### Permissions
Keyboard Shortcut and media actions need Accessibility for the background part. The app asks when the first such
action is set up. It explains the step, opens the right System Settings pane, and shows the result. The background part never asks
on its own, because a prompt from a windowless process goes unseen.

## Signing during development
The owner offered to sign earlier for a healthier test. Recommended from the phase where the agent registers with
macOS and permissions matter. Ad-hoc builds lose Accessibility and similar grants on every rebuild, and Login Items
behaves oddly with them. The method: a Makefile target that signs with the identity named in the gitignored local
file, run by the owner or with the owner's go each time. Ad-hoc (`codesign -s -`) for everything before that phase.

## Development safety
- The installed v1.0.0+N4 daemon runs on this Mac. A second controller reacting to the same decks double-fires every
  press.
- **One go per test session** (owner, 19/11/2026) covers this sequence and nothing else: stop the installed daemon →
  register the development agent → test → unregister it → restart the installed daemon. Claude asks at the start of
  each session, listing the steps, and confirms at the end that the installed daemon is running again. Signing stays
  a separate go each time.
- Development builds use their own bundle id (`io.github.okoker.deckout.dev`) and a test copy of the config, never
  the live file, until install. Debug builds skip the "Move to Applications" check. **(CL call)**

## Testing
- **Automated:** config round-trip for every field; old formats (v1.0.0, today's `decks` without presets, string
  `lock_photo`); preset resolution, including a missing `active_preset`; lock-photo framing slices (zoom, offset,
  clamping); parsing and lock rules for every new action kind; shell-environment capture (markers, timeout,
  fallback) against fake shells; the XPC request/reply types; start-up with no config and with a broken one (runs,
  reports, doesn't exit); key volume / brightness up and down; knob turns refusing non-stepped actions.
- **On the device (owner):** every control on both decks set from the app and seen on the deck; presets switch;
  brightness; lock photo framing on the real N4; Test output, including a command that isn't found; plug and unplug
  with the app open; removal.
- **Fresh installs:** there's no second Mac (owner). The download, first open, Login Items, permission prompts and
  the "Plug in your deck" screen are tested in a macOS virtual machine on this Mac, which can't see the decks. It
  also covers macOS 26 and 27, which friends are likely to run (this Mac runs 15). Setting one up installs a tool:
  ask in phase 7. On 27, check that launchd accepts the agent plist from a downloaded, quarantined app (the macOS 27
  release notes, 166415497, say launchd refuses quarantined plists; untested here). The first friend's install is the real
  check. **(CL call)**

## Phases (the plan details them)
0. BL-001.
1. Background part: config encoding + presets + framing + new actions (media included) + shell environment + XPC
   service + the rename. Tests.
2. App shell: bundle layout, agent registration, `status`, deck buttons, the deck drawing from DeckCore.
3. Editing: keys, strip, knobs, presets menu, brightness, Test, undo. Mock the unmocked panels first.
4. Lock photo mode.
5. Icons: images, text tiles, library.
6. Settings window, bundled `m1ddc`, monitors; first run, including removing the old agent.
7. Signing, notarising, release on GitHub, fresh-install tests in a virtual machine: each act with the owner's go.

## Docs to update when built
`REQUIREMENTS.md` (the "No GUI" non-goal flips; config structure; actions; app), `README.md` (install becomes "drag
to Applications"), `config.example.json`, a `reference/` doc for the app, `TESTS.md`, `PROGRESS.md`. This file gets
a "✅ BUILT" marker. The ideas note gets a pointer here.

## Open questions for the owner
1. Which icon library (by phase 5): Claude proposes one then.
2. Which authority issued the signing certificate (before the first signed build; see Constraints).

## Left to the builder
XPC protocol details; JSON key spellings; agent plist form; log location; icon rendering and storage names; how the
user's shell is found; undo granularity; error wording; Settings layout; the order of work inside each phase.
