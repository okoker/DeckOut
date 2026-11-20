# Backlog

Items discovered during builds, reviews, or revisits. Not blocking current work.
Promote to `TODO.md` when ready to tackle.

Use priority tags: `[P0]` `[P1]` `[P2]` and domain tags: `[security]` `[feature]` `[bug]` `[debt]`

Next free ID: BL-035

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
- BL-014 [P2] [feature] Shortcut recorder: media keys pressed in the recorder show nothing (they arrive as system
  events), rather than "can't be sent"; on non-US layouts the label shows the US character for the key position (the
  key sent is right: both sides work by position). Say media keys aren't recordable; label with the layout's
  character. `ShortcutRecorder.swift` (plan 3 review)
- BL-020 [P2] [debt] The self-test checks that a tile's PNG exists and is in the app's config, not that the agent drew
  it (status or log). `SelfTest.swift` (plan 5 review)
- BL-029 [P2] [feature] Live strip blocks a person can add (the weather, a build status, a price). Today the three
  live readings (internet, CPU and memory, volume) are written into the agent, so each new one needs code. Owner
  (20/11/2026): new kinds are not built into the app. They live in a folder people put them into, in a documented
  standard format; the app picks them up at its next launch and offers them in the strip block's Shows pull-down.
  Starting idea: each one is a command and how often to run it, shown as the text it prints with an optional label;
  paused while the Mac is locked, cut off if it hangs. What's in the folder runs unattended, so the folder gets the
  config's checks (owned by the person, not writable by others). Design with a mockup first; touches the agent,
  which runs them. `StripBlockType`, `StripRenderer`, `Daemon.swift` (UAT, 20/11/2026)
- BL-034 [P1] [bug] Owner's hand-check of the 20/11/2026 fixes in the real app (build 261120.165253 or later); each
  is test-proven but not clicked. BL-031: in Edit in Window…, ⌘Z past the typing leaves the deck change behind it;
  New Preset… and Rename… still open, and ⌘Z in them only undoes typing; the command window stays open through an
  unplug. BL-022: Library on a key with a text icon, closed without a pick, leaves the key as it was; a picked symbol
  then Bold / Fill changes the key at once. BL-015: Edit → Undo is greyed with nothing to undo; after typing in a
  field, ⌘Z undoes the typing. BL-007: a wide picture on an N3 key shows boxed on black, not squashed. BL-017: with
  Lock Photo… open, overwrite the photo's file (same name) and the window shows the new picture without a relaunch.
  BL-012: Make Executable on a script it can't change (someone else's, or on a read-only disk) says why under the
  button. BL-014: a Shortcut made in the Shortcuts app while DeckOut is open shows in the Run a Shortcut picker
  once DeckOut is back in front. Toolbar: Icon Only, its buttons level with the window's close / minimise / zoom
  buttons, and no right-click Icon and Text menu. Then delete the backup `~/.config/vsd-dev.bak-2026-11-20` (the
  start-up icon cleanup removed exactly the 31 predicted files). Run lines in `PROGRESS.md`.
