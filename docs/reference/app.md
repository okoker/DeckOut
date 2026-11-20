# DeckOut app — reference

How the DeckOut app works now. Design and its reasons: `docs/design/config_app.md`. Build plans: plan 2 (the shell),
plan 3 (editing).

## Bundle and identity
- `make app` builds `build/DeckOut Dev.app` (dev variant, debug build); `make app VARIANT=release` builds
  `build/DeckOut.app`. `make install-dev` puts the dev variant in `~/Applications/DeckOut Dev.app` by rename (never a
  copy over a running binary). `scripts/check-bundle.sh` checks a bundle (T-107); `make app` runs it.
- Layout: `Contents/MacOS/DeckOut` (the app), `Contents/MacOS/DeckOutAgent` (the background part),
  `Contents/Library/LaunchAgents/<label>.plist`, `Contents/Resources/AppIcon.icns` (drawn by `scripts/make-icon.swift`).
- `AppIdentity` (DeckCore) derives every name from the bundle id; the agent, a helper in `Contents/MacOS`, sees the
  app's `Bundle.main`.

| | Release | Dev |
|---|---|---|
| Bundle id | `io.github.okoker.deckout` | `io.github.okoker.deckout.dev` |
| Name | DeckOut | DeckOut Dev |
| Agent label = Mach service = agent signing identifier | `io.github.okoker.deckout.agent` | `io.github.okoker.deckout.dev.agent` |
| Config | `~/.config/vsd/config.json` | `~/.config/vsd-dev/config.json` |
| Agent log | `~/Library/Logs/DeckOut/agent.log` | `~/Library/Logs/DeckOut Dev/agent.log` |

- `CFBundleShortVersionString` from `VERSION`; `CFBundleVersion` is the build time (`yymmdd.HHMMSS`), so every build
  differs and the app can tell an older agent.
- Signing: ad hoc only (`codesign -s -`), the helper as its label, then the app. No certificate signing yet.

## Agent plist
`Label`, `BundleProgram` `Contents/MacOS/DeckOutAgent` (bundle-relative: works from `~/Applications`, checked
19/11/2026), `ProgramArguments` `DeckOutAgent --mach-service <label>`, `MachServices` {label}, `RunAtLoad`,
`KeepAlive`, `AssociatedBundleIdentifiers` [bundle id] (macOS ignores it while the agent has no team id). launchd keeps
the job definition it registered: a changed plist needs a new label.

## Launch
1. **Location:** the release app runs only as `/Applications/DeckOut.app` (otherwise "Move DeckOut to Applications");
   the dev variant runs anywhere.
2. **Registration** (`AgentRegistrar`, `SMAppService.agent`): not registered → register; not found → unregister once,
   register, retry up to 10 × 1 s; switched off in Login Items → "Allow DeckOut in Login Items" with a button to the
   settings pane, re-checked whenever the app becomes active; other errors → "The deck controller isn't running" with
   Try Again.
3. **Link** (`AgentLink`): an XPC connection to the agent's Mach service, checked against its signature (by team when
   signed, by identifier when ad hoc). Asks `status` and `liveStrip`, hears `statusChanged` and `liveStripChanged`,
   reconnects when the agent goes away, waiting 1 s, then twice as long after each failed try, up to 30 s. While it
   reconnects the status line says "Reconnecting to the deck controller…"; after 3 s without an answer the last status
   is dropped, so the window stops drawing decks from it. No answer within 10 s of starting or of the drop (one
   deadline for the link, so an agent that refuses every connection at once counts too) → "not answering": the app
   unregisters and registers the agent afresh once (KI-008), then starts its link over. Another build → `restart`
   once per launch; still another build → the status line says so. When the app becomes active while the link is
   down, it looks at the registration again (switched off in Login Items → "Allow DeckOut in Login Items").
4. The config is re-read from disk on every status push (they follow reloads and decks coming and going).

## Window
- 946 × 544 with its toolbar; one window; quitting with it.
- **Toolbar:** a button per deck with its glyph: colour when plugged in, grey and disabled when not, pressed in when on
  screen.
- **Screens:** starting; move to Applications; allow in Login Items; deck controller not running (Try Again); plug in
  your deck (none plugged in); pick a deck (both plugged in at launch); the deck. The deck on screen stays while
  plugged in; unplugged, the other one shows, else "Plug in your deck" (T-118).
- **The deck:** drawn from `DeckFace` (the N4 at half its measured key-image pixels; the N3 by eye from the photo),
  showing each key's icon and the strip's picture blocks as the deck shows them (`DeckPreview`: the N4's own drawing
  code; the N3 preview fits a non-square icon where the deck stretches it, BL-007), and the live blocks from the
  images the agent draws. Knobs carry a caption of what turning them does. A click
  selects a control (red ring); a click on the stage clears it.
- **Editor** (right-hand panel, for the selected control): see Editing.
- **Toolbar, with a deck on screen:** the preset pull-down and the deck's brightness slider (0–100).
- **Status line:** "Deck controller running" (green), starting (amber), or the problem: switched off, not running,
  another build, the config's load problem, a shell environment that fell back.

## Editing
- **The config store** (`ConfigStore`): every change makes a whole new config, saved atomically at 0600 through
  `ConfigFile.save` (which refuses a config that wouldn't load back; the first save over a file keeps
  `.before-app`), then the agent is asked to reload (it logs one line per app reload). Undo / redo (Edit menu, ⌘Z /
  ⇧⌘Z, named for the change) put back whole configs; a text field being edited undoes its typing first; a slider
  drag is one undo step; up to 200 steps. Before each change the file is read again if it changed on disk (a hand
  edit is built on, and the undo history starts again from it, with a notice in the status line); a file that
  doesn't load is never saved over, the status line says why, and it is read again before every change until it
  loads. A failed save is shown; the next change tries again. Coming back to the app picks up a hand edit too.
- **Where edits land:** keys, N3 buttons and strip blocks in the live preset; knobs, brightness on the deck. A deck
  with no section gets one on its first edit ("Default", brightness 75).
- **Actions** (`ActionChoice`): keys, N3 buttons, knob presses and strip taps offer Nothing; Open App, Open Website,
  Open File or Folder; Keyboard Shortcut, Run a Shortcut; Play / Pause, Next Track, Previous Track; Volume Up / Down,
  Mute; Monitor Brightness Up / Down, Switch Monitor; Run Script, Run Command. Knob turns offer Nothing, Volume and
  Monitor Brightness, with a step per click. ZR7 and unknown strings show as "set by hand" until replaced. Fields
  apply when finished (Return, leaving the field, a file chosen); the agent's own reason a string wouldn't run shows
  under the fields.
- **Keyboard shortcuts** are recorded by pressing them; only keys in the agent's own table (`KeyNames`) are taken.
- **Apple Shortcuts** come from `shortcuts list` (run by the app, as an argument array); a text field if none.
- **Icons:** the app's own icon for Open App (rendered to a 256 px PNG in `<config folder>/icons/`, following the app
  unless you chose an image), a picture you choose (decoded and saved as a PNG at most 512 px on a side in `icons/`;
  a file that isn't a picture is refused with a message), or none; the preview is the key as the deck shows it.
- **Strip blocks:** Internet latency (host, arrow threshold in ms, red after s), CPU and memory, Volume, a picture
  (imported like a key's), or nothing; plus what a tap does.
- **Files that are gone:** keys, presses and taps whose app, file, folder, script, icon or picture is missing get a
  red mark on the drawing and the reason in the editor; a script that isn't executable gets Make Executable (adds
  the owner's execute bit); a script or file in Desktop, Documents, Downloads or iCloud Drive gets a note that macOS
  will ask the first time.
- **Test** runs the action in the agent exactly as a press would (minus the lock check) and shows the exit status,
  output or error; commands stop at 30 s.
- **Presets:** the pull-down lists the deck's presets (✓ on the live one), then New Preset ("Preset N", blank, live)
  and Rename (edited in place in the toolbar; Return applies, Esc cancels, an empty or taken name beeps), Duplicate
  ("<name> copy", live) and Delete (not the last; deleting the live one makes the first left live; ⌘Z brings it
  back). Picking one makes it live on the deck.
- **Accessibility:** a keyboard shortcut or media key on a control, with the agent not allowed, shows a note with
  Allow…: the agent asks macOS to list it, the Accessibility pane opens, and the app checks again every 2 s for a
  minute.

## Debug builds
- `--unregister`: take the agent out of launchd and Login Items, then quit (test sessions).
- `--snapshot <png> [--dark] [--deck n3|n4] [--select <control>] [--after <s>]`: draw the real window to a PNG and quit.
- `--selftest`: sets a key, runs Test (`echo`) in the agent, makes, shows and deletes a preset, drags brightness,
  undoes everything and checks the config is back; prints `SELFTEST PASSED` or `FAILED` and quits.
- Window "Agent Status": the status JSON and the link's state.
