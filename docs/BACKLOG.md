# Backlog

Items discovered during builds, reviews, or revisits. Not blocking current work.
Promote to `TODO.md` when ready to tackle.

Use priority tags: `[P0]` `[P1]` `[P2]` and domain tags: `[security]` `[feature]` `[bug]` `[debt]`

Next free ID: BL-033

---

### Fixed (01/04/2026)

- ~~[P0] [security] Config permissions: reject load when writable/wrong owner/symlink. `main.swift`~~
- ~~[P0] [bug] SIGHUP reload race: explicit `shutdown()` before replacing dispatcher. `main.swift`~~
- ~~[P1] [debt] `reportBuffer` replaced with `UnsafeMutablePointer`. `HIDDevice.swift`~~
- ~~[P1] [debt] `Unmanaged.passUnretained` lifetime documented. `HIDDevice.swift`~~
- ~~[P1] [security] HID input report: check `IOReturn` result + min length. `HIDDevice.swift`~~
- ~~[P1] [bug] Shell timeout (30s) + stderr handler cleanup in catch. `ActionDispatcher.swift`~~

### Fixed (02/04/2026)

- ~~[P1] [debt] `key:` silent failure: `AXIsProcessTrusted()` check at startup with clear log message. `ActionDispatcher.swift`~~
- ~~[P1] [bug] Pipe deadlock: read stdout before `waitUntilExit()` in `runProcess`. `BrightnessControl.swift`~~
- ~~[P1] [bug] Stale display mapping: `refreshDisplays()` on mode cycle + cache invalidation on write failure. `BrightnessControl.swift`~~
- ~~[P2] [debt] Icon size cap: reject source images >1024px before full decode. `ImageLoader.swift`~~

### Open

- BL-002 [P2] [feature] No handling for the Mac waking from system sleep. If a deck keeps power through sleep but resets
  without re-enumerating, its keys could show the deck's own logo until the next lock / unlock or replug. On
  `NSWorkspace.didWakeNotification`: re-run the start-up sequence, redraw, recheck the lock. Untested here — this Mac
  never system-sleeps. `Daemon.swift` (19/11/2026)
- BL-003 [P1] [bug] `BrightnessControl` reads 0 for a monitor at start-up and reload and then trusts its cache, so the
  first brightness turn can set a monitor to ~5 %. REQUIREMENTS says brightness is read on first interaction after
  idle. Pre-existing (v1.0.0). `BrightnessControl.swift` (19/11/2026)
- BL-007 [P2] [bug] The app's N3 key preview letterboxes a non-square icon, while the deck's N3 pipeline
  (`ImageLoader.loadAsJPEG`) stretches it into the square, so the drawing differs from the deck for such icons. Draw
  the N3 preview the deck's way. `DeckFace.swift` (`DeckPreview.keyImage`), `ImageLoader.swift` (plan 2 review)
- BL-008 [P2] [bug] The app draws the config file on disk, not the one the agent loaded: after a hand edit without a
  reload, the drawing shows icons the deck doesn't. Plan 3's save-then-reload covers the app's own edits; for hand
  edits, show the agent's config (or its file's state) instead. `AppModel.swift` (plan 2 review)
- BL-012 [P2] [bug] Make Executable does nothing visible when it fails (e.g. a script the person doesn't own). Show
  why. `AppModel+Editing.swift` (plan 3 review)
- BL-014 [P2] [feature] Shortcut list and recorder: the list of Apple Shortcuts is read once per launch (a Shortcut
  made after opening DeckOut needs a relaunch); media keys pressed in the recorder show nothing (they arrive as system
  events), rather than "can't be sent"; on non-US layouts the label shows the US character for the key position (the
  key sent is right: both sides work by position). Re-read the list when the picker opens; say media keys aren't
  recordable; label with the layout's character. `AppModel+Editing.swift`, `ShortcutRecorder.swift` (plan 3 review)
- BL-015 [P2] [debt] Small loose ends from the plan 3 review: the Undo / Redo menu items are never greyed out; each
  Allow… click schedules its own 30 status checks; a slider pause of over a second mid-drag makes two undo steps
  (bracket with `onEditingChanged` instead of a time gap). `Toolbar.swift`, `AppModel+Editing.swift`
- BL-016 [P2] [bug] When the lock-photo preview's file can't be read, the agent tries to load it twice per draw
  (cache miss, then the fallback load): two warnings per move and reload. Return early on a failed preview load.
  `Daemon.swift` (`drawLockPhoto`), `LockPhoto.swift` (plan 4 review)
- BL-017 [P2] [bug] The app's lock-photo cache is never cleared: a hand-set photo path (v1.0.0 string form) whose file
  is replaced keeps showing, and clamping with, the old picture. Key the cache by path and modification date.
  `AppModel.swift` (plan 4 review)
- BL-018 [P2] [debt] Chosen lock photos (and pictures) are never deleted: every Choose leaves a file in the config
  folder. Clean up at quit, keeping anything the config or the undo history still names. `IconFiles.swift`
  (plan 4 review)
- BL-019 [P2] [bug] Undo groups moves, zooms and slider steps by a one-second gap, not by gesture: a pause mid-drag
  makes two steps, two quick drags one. Pass a per-gesture token through `ConfigStore.change` (with BL-015's
  slider). `ConfigStore.swift`, `PhotoStage.swift` (plan 4 review)
- BL-020 [P2] [debt] The self-test checks that a tile's PNG exists and is in the app's config, not that the agent drew
  it (status or log), and each run leaves its tile PNGs in `icons/`. `SelfTest.swift` (plan 5 review)
- BL-022 [P2] [bug] The symbol picker's Bold / Fill switch changes nothing until a symbol is clicked; choosing
  Library and closing the popover leaves the starting star on the key (undoable). `IconRow.swift` (plan 5 review)
- BL-023 [P2] [debt] The icons folder only grows: every colour tap or text edit writes a new `tile-<hash>.png`. Sweep
  files no config or undo step names (with BL-018). `IconFiles.swift` (plan 5 review)
- BL-024 [P2] [debt] The `--selftest` / `--snapshot` skip of the old-controller question isn't inside `#if DEBUG`, so
  a release build launched with those arguments skips it (no person does). Put it under DEBUG. `AppModel.swift`
  (plan 6 review)
- BL-025 [P2] [debt] `AppModel.m1ddcPath` repeats `BrightnessControl.findM1DDC`'s search. Make the DeckCore one
  public and use it. `AppModel+Settings.swift`, `BrightnessControl.swift` (plan 6 review)
- BL-029 [P2] [feature] Live strip blocks a person can add (the weather, a build status, a price). Today the three
  live readings (internet, CPU and memory, volume) are written into the agent, so each new one needs code. Owner
  (20/11/2026): new kinds are not built into the app. They live in a folder people put them into, in a documented
  standard format; the app picks them up at its next launch and offers them in the strip block's Shows pull-down.
  Starting idea: each one is a command and how often to run it, shown as the text it prints with an optional label;
  paused while the Mac is locked, cut off if it hangs. What's in the folder runs unattended, so the folder gets the
  config's checks (owned by the person, not writable by others). Design with a mockup first; touches the agent,
  which runs them. `StripBlockType`, `StripRenderer`, `Daemon.swift` (UAT, 20/11/2026)
- BL-031 [P2] [bug] Sheets and undo: ⌘Z in the command window or a preset sheet, with nothing left to undo in its
  field, undoes the last deck change behind it (the command window can then close, its typing gone); the command
  window also closes, losing its text, when the deck on screen changes (unplug, agent restart). Skip the store's
  undo while a sheet is key (`NSApp.keyWindow?.sheetParent != nil`); host the command sheet on the main window like
  the preset sheet. `Toolbar.swift` (`UndoCommands`), `CommandEditor.swift` (plan 7 review, 20/11/2026)
