# Backlog

Items discovered during builds, reviews, or revisits. Not blocking current work.
Promote to `TODO.md` when ready to tackle.

Use priority tags: `[P0]` `[P1]` `[P2]` and domain tags: `[security]` `[feature]` `[bug]` `[debt]`

Next free ID: BL-016

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
  without re-enumerating, its keys could show the deck's own logo until the next lock / unlock, reload or replug. On
  `NSWorkspace.didWakeNotification`: re-run the start-up sequence, redraw, recheck the lock. Untested here — this Mac
  never system-sleeps. `Daemon.swift` (19/11/2026)
- BL-003 [P1] [bug] `BrightnessControl` reads 0 for a monitor at start-up and reload and then trusts its cache, so the
  first brightness turn can set a monitor to ~5 %. REQUIREMENTS says brightness is read on first interaction after
  idle. Pre-existing (v1.0.0). `BrightnessControl.swift` (19/11/2026)
- BL-004 [P2] [bug] The N4's internet tile sometimes shows red ("no reply") for its first reading after the daemon
  starts (2 of ~7 starts), never afterwards. Log which step failed (lookup, `sendto`, timeout, `recv`) with `errno`,
  and show "–" rather than red for a new probe's first reading. `LatencyProbe.swift`, `Daemon.swift` (19/11/2026)
- BL-005 [P2] [debt] A reload redraws every screen on every deck (N3 6, N4 14): 75–158 ms measured 19/11/2026, on
  the main thread, so a press during a reload waits for it. Redraw only the screens whose content changed (compare
  each deck's layout plan before and after). Matters once the config app reloads on every edit (plan 3): most edits
  change one key. `Daemon.reload`, `Daemon.drawAll`, `LayoutPlan` (19/11/2026)
- BL-006 [P2] [security] The agent adds a connection to the clients it pushes status to as soon as it accepts it,
  before XPC has checked the first message against the code-signing requirement, so a refused peer can receive one
  status or live-strip push before it is cut off (no calls run). Add a client on its first checked call instead
  (`NSXPCConnection.current()` inside `status`). `AgentXPC.swift` (plan 2 review, 19/11/2026)
- BL-007 [P2] [bug] The app's N3 key preview letterboxes a non-square icon, while the deck's N3 pipeline
  (`ImageLoader.loadAsJPEG`) stretches it into the square, so the drawing differs from the deck for such icons. Draw
  the N3 preview the deck's way. `DeckFace.swift` (`DeckPreview.keyImage`), `ImageLoader.swift` (plan 2 review)
- BL-008 [P2] [bug] The app draws the config file on disk, not the one the agent loaded: after a hand edit without a
  reload, the drawing shows icons the deck doesn't. Plan 3's save-then-reload covers the app's own edits; for hand
  edits, show the agent's config (or its file's state) instead. `AppModel.swift` (plan 2 review)
- BL-009 [P2] [debt] The agent JSON-encodes the whole live strip (~40 KB) on every live redraw, once per strip slot in
  `drawAll`, even when no app is connected. Skip when there are no clients; push once per redraw. `AgentXPC.swift`,
  `Daemon.swift` (plan 2 review)
- BL-010 [P2] [debt] The app's registration work (the not-answering hook, Try Again, the re-check when the app becomes
  active) can interleave unregister / register calls. Serialise them (one task at a time). `AppModel.swift` (plan 2
  review)
- BL-011 [P2] [bug] Preset rename in the toolbar drops the typed name when focus leaves the field (Finder and Xcode
  apply it), and it renames whichever preset is live when committed, so ⌘Z right after New Preset makes the rename
  hit the previous preset. Apply on focus loss; rename the preset that was live when editing began. `Toolbar.swift`
  (plan 3 review)
- BL-012 [P2] [bug] Make Executable does nothing visible when it fails (e.g. a script the person doesn't own). Show
  why. `AppModel+Editing.swift` (plan 3 review)
- BL-013 [P2] [bug] An emptied Host field on an internet strip block saves an empty host, and the block stays red,
  though the placeholder suggests the default is used. Save the default host for an empty field. `StripEditor.swift`
  (plan 3 review)
- BL-014 [P2] [feature] Shortcut list and recorder: the list of Apple Shortcuts is read once per launch (a Shortcut
  made after opening DeckOut needs a relaunch); media keys pressed in the recorder show nothing (they arrive as system
  events), rather than "can't be sent"; on non-US layouts the label shows the US character for the key position (the
  key sent is right: both sides work by position). Re-read the list when the picker opens; say media keys aren't
  recordable; label with the layout's character. `AppModel+Editing.swift`, `ShortcutRecorder.swift` (plan 3 review)
- BL-015 [P2] [debt] Small loose ends from the plan 3 review: the Undo / Redo menu items are never greyed out; each
  Allow… click schedules its own 30 status checks; a slider pause of over a second mid-drag makes two undo steps
  (bracket with `onEditingChanged` instead of a time gap). `Toolbar.swift`, `AppModel+Editing.swift`
