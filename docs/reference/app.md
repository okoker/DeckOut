# DeckOut app — reference

How the DeckOut app works now. Design and its reasons: `docs/design/config_app.md`. Build plan: plan 2 (the shell);
editing comes with plan 3.

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
- **Inspector:** what the selected control does, read-only (plan 3 makes it the editor).
- **Status line:** "Deck controller running" (green), starting (amber), or the problem: switched off, not running,
  another build, the config's load problem, a shell environment that fell back.

## Debug builds
- `--unregister`: take the agent out of launchd and Login Items, then quit (test sessions).
- `--snapshot <png> [--dark] [--deck n3|n4] [--select <control>] [--after <s>]`: draw the real window to a PNG and quit.
- Window "Agent Status": the status JSON and the link's state.
