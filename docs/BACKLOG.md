# Backlog

Items discovered during builds, reviews, or revisits. Not blocking current work.
Promote to `TODO.md` when ready to tackle.

Use priority tags: `[P0]` `[P1]` `[P2]` and domain tags: `[security]` `[feature]` `[bug]` `[debt]`

Next free ID: BL-039

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
  (20/11/2026): new kinds are not built into the app; they are scripts in a `blocks/` folder, which the agent runs on
  an interval and draws as short text. Idea, with the looks the owner approved on the N4 (text, `color=`, emoji,
  `icon=` symbols, a test card on failure) and the open scripting and scheduling questions:
  `docs/ideas/script_blocks.md`. Initial work: its first slice (a weather script, the agent's runner, a `script` block
  set by hand). After the phase 7 release, once the scripting and scheduling are worked out (owner, 21/11/2026).
  `StripBlockType`, `StripRenderer`, `Daemon.swift` (UAT, 20/11/2026)
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
- BL-035 [P2] [bug] After a swipe makes another preset live, text half-typed in an editor field can commit to the same
  key in the newly live preset: the editor is rebuilt per control, not per preset. ⌘Z undoes it. Rebuild it when the
  live preset changes too. `EditorPanel.swift` (`.id(model.selection)`) (BL-033 review, 21/11/2026)
- BL-036 [P2] [feature] A `next_preset` typed by hand onto a key or a knob works on the deck, but the window shows it as
  "Unknown action". Give it a name in the window (it stays out of the menus). `ActionNames.swift` (BL-033 review,
  21/11/2026)
- BL-037 [P2] [debt] Test gaps in the swipe's preset switch: T-190 has no missing-file or symlinked-config case (the
  agent must write nothing); T-191 doesn't check `next_preset` never reaches the dispatcher (a command run).
  `AgentTests.swift` (BL-033 review, 21/11/2026)
- BL-038 [P2] [feature] README: a "Recipes" section of sanitized key examples, each with the action to pick and the
  trap found setting it up (owner, 21/11/2026). A VMware Fusion VM: Open File or Folder on its `.vmwarevm` (it powers
  on; `vmrun` can outlast the 30 s command limit). ssh in an iTerm2 window with a given profile (`osascript` `create
  window with profile … command`; the `zsh -lc "…; exec zsh"` form stays open after logout). A link in a given Chrome
  profile: `open -na "Google Chrome" --args --profile-directory=… <url>` (the folder name from `chrome://version`;
  without `-n` the args are dropped; never Chrome's own binary, the limit would close Chrome). That link on a given
  Desktop: ⌃N through System Events, then `open -gna … --new-window`, `open -a`; it needs "Switch to Desktop N" on in
  Keyboard Shortcuts (numbers run across monitors) and Accessibility for DeckOut itself (macOS checks the app the agent
  lives in, not DeckOutAgent; a dev build needs the entry removed and added again). What can't be done: a Proton VPN
  country connection (the Mac app takes only `protonvpn://refresh`, has no Shortcuts or AppleScript; the CLI is Linux
  only), with the Auto Connect workaround. Straight quotes only. No host, user, profile, VM or URL names from the
  owner's config. `README.md`
