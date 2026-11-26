# DeckOut app — reference

How the DeckOut app works now. Design and its reasons: `docs/design/config_app.md`. Build plans: plan 2 (the shell),
plan 3 (editing), plan 4 (lock photo), plan 5 (icons), plan 6 (settings, monitors, first run).

## Bundle and identity
- `make app` builds `build/DeckOut Dev.app` (dev variant, debug build); `make app VARIANT=release` builds
  `build/DeckOut.app`. `make install-dev` puts the dev variant in `~/Applications/DeckOut Dev.app` by rename (never a
  copy over a running binary). `scripts/check-bundle.sh` checks a bundle (T-107); `make app` runs it.
- `make uninstall-dev` removes the dev variant from this Mac, in this order: the installed app's `--unregister` (out of
  launchd and Login Items), `tccutil reset` of its Accessibility and Automation grants (they need the app still on
  disk), then deletes the installed app, the build copy, its log folder, saved window state, caches and defaults.
  `~/.deckout-dev` stays. If the agent is still registered after `--unregister` (which quits the same way when it
  fails), it stops before deleting anything: no app would be left to unregister it. Deleted, not binned: a binned DeckOut Dev still opens and registers its agent again.
- Layout: `Contents/MacOS/DeckOut` (the app), `Contents/MacOS/DeckOutAgent` (the background part),
  `Contents/Library/LaunchAgents/<label>.plist`, `Contents/Resources/AppIcon.icns` (drawn by `scripts/make-icon.swift`).
- `AppIdentity` (DeckCore) derives every name from the bundle id; the agent, a helper in `Contents/MacOS`, sees the
  app's `Bundle.main`.

| | Release | Dev |
|---|---|---|
| Bundle id | `io.github.okoker.deckout` | `io.github.okoker.deckout.dev` |
| Name | DeckOut | DeckOut Dev |
| Agent label = Mach service = agent signing identifier | `io.github.okoker.deckout.agent` | `io.github.okoker.deckout.dev.agent` |
| Config | `~/.deckout/config.json` | `~/.deckout-dev/config.json` |
| Agent log | `~/Library/Logs/DeckOut/agent.log` | `~/Library/Logs/DeckOut Dev/agent.log` |

- `CFBundleShortVersionString` from `VERSION`; `CFBundleVersion` is the build time (`yymmdd.HHMMSS`), so every build
  differs and the app can tell an older agent.
- Signing: `make app` signs ad hoc (`codesign -s -`): m1ddc, the agent as its label, then the app. Developer ID
  signing is `make signed` (below).

## Signing and release
- `make signed VARIANT=release` (the owner's go, each run) refuses unless the variant is release, `SIGN_ID` is set and
  no tracked file has uncommitted changes. It first deletes the last disk image (so after a failed run `make notarize` finds
  nothing to submit), then builds the release app, then signs inside out, never `--deep`: m1ddc
  (`-i io.github.okoker.deckout.m1ddc`), the agent (`-i io.github.okoker.deckout.agent`), the app, each with
  `codesign --force --timestamp -o runtime` (hardened runtime, secure timestamp). T-193 then requires Apple's marks for
  a Developer ID Application certificate, not just a team id. The agent and the app carry
  `Packaging/DeckOut.entitlements`, which holds only `com.apple.security.automation.apple-events`: keys' commands drive
  other apps through `osascript`. `NSAppleEventsUsageDescription` is the text macOS shows when it asks. Then
  `check-bundle.sh --signed` (T-193), and the disk image `build/DeckOut-<VERSION>.dmg` (UDZO, volume "DeckOut"):
  `DeckOut.app` beside an `Applications` link, the image itself signed with a timestamp.
- `make notarize` (the owner's go, each run) submits the image with `notarytool --wait` under `NOTARY_PROFILE`, staples
  and validates the ticket, requires Gatekeeper's `source=Notarized Developer ID`, and prints the SHA-256. A rejected
  submission has no ticket, so stapling fails and make stops; `xcrun notarytool log <id>` says why.
- `signing.mk` (gitignored; template `signing.mk.example`) sets `SIGN_ID`, the certificate's SHA-1, and
  `NOTARY_PROFILE`, the Keychain profile that `notarytool store-credentials` made. Both are trimmed, so a trailing
  space or a space before a `# comment` does no harm. The repo never names the
  certificate: the checks drop `codesign`'s `Authority=` lines and `spctl`'s `origin=` line.

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
   Try Again. The registration steps (launch, Try Again, the not-answering recovery, the re-check when the app becomes
   active, Retire It / Not Now, Stop and Remove, Start Again) run one at a time, in the order they were asked for.
3. **Link** (`AgentLink`): an XPC connection to the agent's Mach service, checked against its signature (by team when
   signed, by identifier when ad hoc). Asks `status` and `liveStrip`, hears `statusChanged` and `liveStripChanged`,
   reconnects when the agent goes away, waiting 1 s, then twice as long after each failed try, up to 30 s. While it
   reconnects the status line says "Reconnecting to the deck controller…"; after 3 s without an answer the last status
   is dropped, so the window stops drawing decks from it. No answer within 10 s of starting or of the drop (one
   deadline for the link, so an agent that refuses every connection at once counts too) → "not answering": the app
   unregisters and registers the agent afresh once, then starts its link over. After a new ad hoc build this can
   land before launchd's own retry and be refused again, and Try Again can't win (KI-008: quit and reopen). Another build → `restart`
   once per launch; still another build → the status line says so. When the app becomes active while the link is
   down, it looks at the registration again (switched off in Login Items → "Allow DeckOut in Login Items").
4. The config is re-read from disk on every status push (they follow reloads and decks coming and going).

## Window
- 946 × 540 with its toolbar; one window; quitting with it.
- **Toolbar:** a button per deck with its glyph: colour when plugged in, grey and disabled when not, pressed in when on
  screen. Fixed at Icon Only, with macOS's right-click Icon and Text / Icon Only menu off: the buttons draw their own
  picture and name, so the menu had nothing to switch. Icon Only, not Icon and Text, because Icon and Text keeps an
  empty label row that lifts the buttons ~5 pt above the window's close / minimise / zoom buttons.
- **Screens:** starting; move to Applications; allow in Login Items; deck controller not running (Try Again); plug in
  your deck (none plugged in); pick a deck (both plugged in at launch); the deck. The deck on screen stays while
  plugged in; unplugged, the other one shows, else "Plug in your deck" (T-118).
- **The deck:** drawn from `DeckFace` (the N4 at half its measured key-image pixels; the N3 by eye from the photo),
  showing each key's icon and the strip's picture blocks as the deck shows them (`DeckPreview`: the N4's own drawing
  code; both decks and their previews keep a non-square icon's shape, on black), and the live blocks from the
  images the agent draws. Knobs carry a caption of what turning them does (a list: "List of 5"). A click
  selects a control (red ring); a click on the stage clears it.
- **Editor** (right-hand panel, for the selected control): see Editing. It is built afresh for each control and
  each live preset (`AppModel.editorIdentity`): after a swipe, text half-typed for one preset never lands in the next.
- **Toolbar, with a deck on screen:** the preset pull-down and the deck's brightness slider (0–100).
- **Status line:** "Deck controller running" (green), starting (amber), or the problem: switched off, not running,
  another build, the config's load problem, a shell environment that fell back.

## Editing
- **The config store** (`ConfigStore`): every change makes a whole new config, saved atomically at 0600 through
  `ConfigFile.save` (which refuses a config that wouldn't load back; the first save over a file keeps
  `.before-app`, and the first by 2.2 `.before-2.2`), then the agent is asked to reload (it logs one line per app reload). Undo / redo (Edit menu, ⌘Z /
  ⇧⌘Z, named for the change) put back whole configs; a text field being edited undoes its typing first; in a sheet
  (the command window, a preset's name) ⌘Z / ⇧⌘Z only touch its typing, never the deck behind it; slider steps
  less than a second apart are one undo step (KI-012); up to 200 steps. Undo / Redo are greyed out with nothing to
  undo / redo, but stay on once any field has been typed in, until it's left (macOS's begin / end editing
  notices): a greyed item would swallow ⌘Z, and a field has no ⌘Z of its own. Before each change the file is read again if it changed on disk (a hand
  edit, or a swipe's preset switch saved by the agent, is built on, and the undo history starts again from it, with a notice in the status line); a file that
  doesn't load is never saved over, the status line says why, and it is read again before every change until it
  loads. A failed save is shown; the next change tries again. Coming back to the app picks up a hand edit too.
- **Where edits land:** keys, N3 buttons, knobs and strip blocks in the live preset; brightness on the deck. A deck
  with no section gets one on its first edit ("Default", brightness 75; on the N4 a swipe set to `next_preset` and
  the baseline below as its preset). A section already in the file is never replaced.
- **Actions** (`ActionChoice`): keys, N3 buttons, knob presses and strip taps offer Nothing; Open App, Open Website,
  Open File or Folder; Keyboard Shortcut, Run a Shortcut; Play / Pause, Next Track, Previous Track; Volume Up / Down,
  Mute; Monitor Brightness Up / Down, Switch Monitor; Run Script, Run Command. Knob turns offer Nothing, Volume and
  Monitor Brightness, with a step per click, and on the N4 Pick from a list (below). ZR7 and unknown strings show as "set by hand" until replaced. Fields
  apply when finished (Return, leaving the field, a file chosen); the agent's own reason a string wouldn't run shows
  under the fields. Multi-line fields (a command, a text icon) wrap and grow; Option-Return starts a new line. Each
  editor ends with its Clear (Key, Button, Knob or Block, in red) at the bottom of the panel; the panel scrolls when
  its content is taller than the window.
- **Run Command:** the command spans the panel (3–10 lines, then it scrolls). Edit in Window… applies what was
  typed in the panel, then opens a 640 × 380 editor: monospaced, wrapped, and typed exactly (smart quotes, dashes,
  text replacements and spelling fixes off whatever the macOS settings); Save (the prominent button, ⌘Return)
  applies it, Cancel (Esc) changes nothing. The editor hangs on the main window (`AppModel.commandEdit`), not on
  the key's panel, so it stays open, typing and all, if the deck unplugs or the agent restarts; Save writes to the
  control it was opened for.
- **Keyboard shortcuts** are recorded by pressing them; only keys in the agent's own table (`KeyNames`) are taken.
- **Apple Shortcuts** come from `shortcuts list` (run by the app, as an argument array); a text field if none. It is
  read each time a Shortcut picker appears and each time DeckOut comes to the front after one has, so a Shortcut made
  meanwhile is offered without a relaunch; the list on screen stays while it's read again. Until a picker needs it,
  the tool isn't run.
- **Icons** ([App | Image | Text | Library], and No Icon): the app's own icon for Open App (rendered to a 256 px PNG
  in `<config folder>/icons/`, following the app unless you chose another icon); a picture you choose (decoded and
  saved as a PNG at most 512 px on a side in `icons/`; a file that isn't a picture is refused with a message); text
  (wrapped at spaces into up to three lines, as large as fits down to a readable minimum, then cut with an ellipsis;
  a new one starts with the key's app, file or site name, or its action's name: "Key" for none, "Block" on a strip
  block with no tap) or a library symbol (centred on its outline) on one of ten
  colours, drawn by the app as `icons/tile-<hash>.png` (256 px, sRGB, white or near-black text by the background
  unless chosen; a `tile` that doesn't read is ignored) with the key's `tile` recording how, so it opens
  for editing again; changing the key's action keeps it. The library is Phosphor 2.1.2 (1,530 symbols, Bold and
  Fill, MIT), searched in a popover. Choosing Library only opens it: the key keeps its icon until a symbol is
  clicked (a new symbol starts in Fill on dark grey; one already on the key keeps its colours), and Bold / Fill
  restyles the symbol on the key at once. In a build without it, choosing Library changes nothing and says "The symbol
  library isn't in this build." A tile that can't be drawn changes nothing and says why. The preview is the key as the
  deck shows it.
- **Unused icon files** (`IconFiles.removeUnused`, from `AppModel.removeUnusedIcons`): at start-up, right after the
  config is read and before any edit (once per run, and only with nothing to undo or redo), DeckOut deletes the
  files it made that nothing names any more: `app-` / `image-` / `tile-<16 hex>.png` in `icons/` and
  `lock-photo-<16 hex>.jpg` beside the config. A file is kept if its name appears anywhere in any other file in the
  config folder or its subfolders (the config, `.before-app`, `.before-2.2`, copies kept there): the bytes are searched, not the
  config's fields. Never touched: other names, the right name in the wrong folder, links. Nothing is removed when the
  config is missing or doesn't load, or another file there can't be read. The app's log lists what went. Each app
  judges by its own config folder only (DeckOut Dev's and the signed DeckOut's are separate).
- **Strip blocks** are laid out like a key: **Tap** (the key's actions) first, then **Shows**: An image (the key's
  [App | Image | Text | Library], App only for an Open App tap; text and symbols drawn at 352 × 224, 2× the block's
  176 × 112, text sizes scaled to the shorter side, with the block's own `tile`), Internet latency (host, trimmed —
  an emptied field saves the default its placeholder shows, `one.one.one.one`; arrow threshold in ms, red after s),
  CPU and memory, Volume, or Nothing. The two are independent, except that a block showing an app's own icon follows
  its tap to another app, as a key does, in the same undo step (your image, text or symbol stays). Setting a tap
  never puts an image on a block (a new block stays blank until its image is picked, a live reading stays); a live
  reading drops the image.
- **Knob lists (N4)** (`KnobListEditor`): Turn → Pick from a list (after the menu) makes the knob a list, empty, and
  clears the strip block above it in the same undo step; picking any other Turn action replaces the list. The Press
  row gives way to a note (the knob's press, or a tap of the block above, opens the pick) and the list: a row per item
  with its picture as the block shows it and a name (the site's host, the app's or file's name, else the action), the
  item the deck shows marked "On the deck" (the agent's pick, apart from the row being edited); + adds an item after
  the selected one, − removes it, ↑ / ↓ move it, each one undo step. The selected item has a key's action menu and
  fields, an icon like a strip block's ([App | Image | Text | Library], drawn at 352 × 224) and Test. An Open App
  item shows its app's icon until another is chosen; any other item stays black on the deck until an icon is
  chosen. In the drawing, the block above shows the deck's pick (the first item until the agent says) and the knob's
  caption the list's size. The block above, selected, says "Shows knob N's list" with Edit Knob N in place of its
  settings.
- **Files that are gone:** keys, presses, taps and knob list items whose app, file, folder, script, icon or picture is
  missing (a list knob names its first such item: "Item 2: the app isn't there any more") get a
  red mark on the drawing and the reason in the editor; a script that isn't executable gets Make Executable (adds
  the owner's execute bit; when that fails it says why under the button, e.g. "Only the script's owner can make it
  executable.", until another control is selected); a script or file in Desktop, Documents, Downloads or iCloud Drive gets a note that macOS
  will ask the first time.
- **Test** runs the action in the agent exactly as a press would (minus the lock check) and shows the exit status,
  output or error; commands stop at 30 s.
- **Presets:** the pull-down shows the live preset and never leaves the toolbar. Its menu (owner, 20/11/2026): the
  live preset (✓), then Default (the first preset in the file, whatever it's called) when another is live; New
  Preset…, Rename "‹live›"…, Duplicate "‹live›" ("<name> copy", live, no question), Delete "‹live›" (not the last;
  deleting the live one makes the first left live; ⌘Z brings it back); a line; the other presets in file order.
  New Preset… and Rename… open a sheet with the name ("Preset N" offered for a new one): Cancel (Esc) changes
  nothing; Create / Rename (Return) is greyed out, with the reason, while the name is empty or taken. A new preset
  is live. On the N4 it is the same baseline whatever the live preset holds (`AppConfig.baselineN4`, owner,
  26/11/2026): knob 2 monitor brightness (press: switch monitor), knob 4 volume step 5 (press: mute), block 1
  latency (no tap), block 2 CPU / memory (tap: Activity Monitor); knobs 1 and 3, blocks 3–4 and the keys empty.
  Nothing personal ships in it (no ZR7, no scripts): a person's own settings stay in their file. On the N3 it is
  blank but for the live preset's knobs' built-in halves (volume, mute, monitor brightness, switch monitor; a knob
  with another action comes over as nothing). Duplicate copies everything, lists included. Rename renames the preset the sheet was opened for. Picking one makes it live on the
  deck.
- **Accessibility:** a keyboard shortcut or media key on a control, with the agent not allowed, shows a note with
  Allow…: the agent asks macOS to list it, the Accessibility pane opens, and the app checks again every 2 s for a
  minute (one watch: another click starts the minute again). macOS checks the app the agent lives in (DeckOut,
  DeckOut Dev), not DeckOutAgent, so that's the entry to switch on; a command's keystrokes (`osascript` → System
  Events) are checked the same way (21/11/2026). An ad hoc build's entry stays on after a rebuild but no longer
  matches: remove it and add the app again.

## Lock photo mode (N4)
- **Lock Photo…** in the toolbar (N4 on screen) switches the window into photo mode; Done (or switching deck,
  or the N4 going) switches back. The preset menu is dimmed meanwhile.
- **The deck** shows the photo across its 14 screens as they cut it: the app draws `LockPhoto.panel`, the same
  picture the agent slices. "Show hidden parts" draws the whole panel faintly under the screens. Drag to move (400 pt
  of drag = the face's width), pinch, scroll or the slider to zoom (100–400 % on the slider, up to 1000 % by pinch).
- **Framing** is kept within its limits (`LockPhoto.clamped`): the photo always covers the face. A drag applies each
  move's change to where the photo is, so past the edge and back it follows at once. Moves (or zooms) less than a
  second apart are one undo step (KI-012); Reset centres it at 100 %; Remove Photo takes it off
  (undoable). Scroll zoom is exponential and ignores momentum.
- **Choose…** saves the photo in the config folder as `lock-photo-<hash>.jpg` (0600), at most 3200 px on a side,
  read through ImageIO; a file over 100 MB or one that isn't a picture is refused with a message. The original can
  go.
- **Show on the deck** (on by default): the real N4 shows what the window shows, whatever changed it (a move, undo,
  a hand edit, a reconnect), at most every 50 ms with the last one always sent; it goes back to its keys on Done, and
  when the only deck goes away. The agent decodes the photo once per preview, and the app once while it's open; both decode it again when the
  file at that path is replaced or rewritten (told by its file number, size and modified time, not by reading it).

## First run and removal
- **The hand-installed controller** (the README's `com.streamdeck.controller`: 1.0, from when the app was
  StreamDeckController, before it was renamed DeckOut): when its plist is in
  `~/Library/LaunchAgents`, DeckOut asks before registering its own ("Another deck controller is installed"):
  **Retire It** boots it out of launchd by its plist (`launchctl bootout gui/<uid> <plist>`), checks launchd no
  longer has it (if it does: "still running", nothing moved), and moves its plist to `….plist.retired-by-deckout`
  (kept for rollback; its program and the config stay), then registers DeckOut's; it runs off the main thread and
  its buttons wait while it does; a second Retire It leaves the kept copy alone; **Not Now** registers DeckOut's anyway and the status line
  keeps warning that presses may fire twice. Automated debug runs (`--selftest`, `--snapshot`) skip the question; a release build has no such runs and always asks.
- **Removal:** Settings → General → Stop and Remove… (confirmed) stops the link and unregisters the agent (out of
  launchd and Login Items) and shows "The deck controller is stopped" with Quit and Start Again; then the person bins
  the app. Nothing registers it again (the not-answering recovery, coming back to the app, the window opening again)
  until Start Again. The window shows it stopping at once ("Stopping the deck controller…", Quit and Start Again
  disabled) until macOS has answered the unregister: a registration step already under way finishes first, then the
  link is stopped again and the agent unregistered, last. If macOS refuses, Settings → General says so in red, unless
  Start Again was pressed meanwhile. Removal is asked for once: Settings' Stop and Remove… is disabled while removed,
  and asking again does nothing, until Start Again. The config stays in `~/.deckout` (dev: `~/.deckout-dev`).
  Not verified: what macOS does when the app is binned while still registered (Stop and Remove first).
- **Updating:** Finder refuses to replace the app while its agent runs ("The operation can't be completed because
  the item "DeckOut.app" is in use", 2.1.0 → 2.2.0 on 26/11/2026), and killing the agent doesn't help (launchd's
  `KeepAlive` starts it again). So the README says: Stop and Remove…, quit, replace, open, Start Again. Replaced from
  the command line (`ditto`) while the agent runs, the bundle is swapped, and opening the app restarts the agent on the
  new build (2.0.0 → 2.1.0).
- Brightness actions with no monitor control say why: none set up (Settings → Monitors), or set up but unreachable
  (m1ddc missing, or no monitor answered).

## Settings (⌘,)
- **General:** the deck controller's state, version and build; whether the shell's settings were read (Read Again);
  Accessibility (Allow…); Stop and Remove….
- **Monitors:** the monitors the app's own `m1ddc` lists (`display list detailed`), each checked with a read-only
  brightness read (`get luminance`, 3 s at most; one that doesn't answer says so and can't be turned on); told
  apart by where they sit (Left / Right / Middle, Top / Bottom); listed in Switch Monitor's order (the ones in use
  first); turning one on adds it to `displays` (named by its place) at the end of that order; a name field and up /
  down reorder; monitors in `displays` that aren't connected show with Forget; Look Again; the list refreshes when
  Settings opens and when screens change. A monitor without a serial ("(null)") isn't listed.
- **About:** version and build; the DeckOut, Phosphor and m1ddc licences, from the app's Resources, in 9.5 pt
  fixed-width type, so their 78-character lines fit the tab without breaking (T-174).
- **m1ddc** 1.3.1 (MIT), patched (About says so), is built from `Vendor/m1ddc` into `Contents/Helpers/m1ddc`; the
  agent and the app use it before Homebrew's (the agent logs which; both by the same search,
  `BrightnessControl.findM1DDC`). The patch makes a read wait 50 ms, decode only a
  valid reply, and ask again up to 4 times; a read that gets none exits 1 instead of printing `0`
  (`Vendor/m1ddc/README.md`). Homebrew's stock m1ddc can still print a bad `0`; the agent never moves a monitor from a
  reading outside 0–100 or a failed one, but can't tell a bad `0` from a real one.

## Debug builds
- DeckOut Dev is on this Mac only during a dev session. With the signed DeckOut running the decks, a session
  starts with Stop and Remove in DeckOut, then `make install-dev`, and ends with `make uninstall-dev`, then DeckOut is
  opened again: two agents would fire every press twice.
- `--unregister`: take the agent out of launchd and Login Items, then quit (test sessions).
- `--snapshot <png> [--dark] [--deck n3|n4] [--select <control>] [--photo] [--show-old-controller] [--after <s>]`:
  draw the real window to a PNG and quit (`--photo`: in photo mode, without previewing on the N4).
- `--selftest`: sets a key, runs Test (`echo`) in the agent, makes, shows and deletes a preset, drags brightness,
  chooses a generated lock photo and moves it with the N4 previewing it, puts a text and a symbol tile on a key,
  lists the monitors through the app's own m1ddc, undoes everything and checks the config is back; prints
  `SELFTEST PASSED` or `FAILED` and quits.
- Window "Agent Status": the status JSON and the link's state.
