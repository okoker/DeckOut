# Backlog

Items discovered during builds, reviews, or revisits. Not blocking current work.
Promote to `TODO.md` when ready to tackle.

Use priority tags: `[P0]` `[P1]` `[P2]` and domain tags: `[security]` `[feature]` `[bug]` `[debt]`

Next free ID: BL-043

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
- BL-036 [P2] [feature] A `next_preset` typed by hand onto a key or a knob works on the deck, but the window shows it as
  "Unknown action". Give it a name in the window (it stays out of the menus). `ActionNames.swift` (BL-033 review,
  21/11/2026)
- BL-037 [P2] [debt] Test gaps in the swipe's preset switch: T-190 has no missing-file or symlinked-config case (the
  agent must write nothing); T-191 doesn't check `next_preset` never reaches the dispatcher (a command run).
  `AgentTests.swift` (BL-033 review, 21/11/2026)
- BL-038 [P2] [feature] README: a "Recipes" section of sanitized key examples, each with the action to pick and the
  trap found setting it up (owner, 21/11/2026). The README already has one: Chrome in a given profile on a given
  Desktop. Still to add: a VMware Fusion VM: Open File or Folder on its `.vmwarevm` (it powers on; `vmrun` can outlast
  the 30 s command limit). ssh in an iTerm2 window with a given profile (`osascript` `create window with profile …
  command`; the `zsh -lc "…; exec zsh"` form stays open after logout). What can't be done: a Proton VPN
  country connection (the Mac app takes only `protonvpn://refresh`, has no Shortcuts or AppleScript; the CLI is Linux
  only), with the Auto Connect workaround. Straight quotes only. No host, user, profile, VM or URL names from the
  owner's config. `README.md`
- BL-039 [P1] [bug] The first release signed with a new Developer ID certificate is an update across a certificate
  switch: test it as 2.1.0's update was tested (26/11/2026, KI-008: the app replaced while its agent ran, then opened
  once; the new agent ran at the first try). Expected: the agent runs on the new build within 15 s, launchd's `runs`
  goes up by one (macOS logs unrelated `Constraint not matched` lines too, so the count is the test), Accessibility is
  kept, Login Items has one entry; compare `codesign -dr -` of the old and new agent. The certificate expires
  01/02/2027 (original Sub-CA); its G2 replacement, and every G2 certificate after it, lasts one year (Apple, "Replace
  Developer ID certificates"), so this comes back after each yearly renewal. If it fails: `AgentLink` re-registers
  every 15 s while the agent doesn't answer (`init(…, recoveryInterval: TimeInterval = 15)`; a test from T-112's mute
  listener expecting repeated hooks until it answers). `AgentLink.swift`, `AgentRegistrar.swift` (owner, 21/11/2026)
- BL-040 [P2] [debt] Use upstream m1ddc 1.3.3 (released 21/11/2026) unpatched, in place of 1.3.1 with DeckOut's
  patch. 1.3.3 carries that patch's read fix (waydabber/m1ddc#81, merged 21/11/2026), plus `--read-wait <ms>`
  (default 50), "Unsupported VCP code" at once with exit 1 for a result `01`, and up to 8 monitors (1.3.2). Vendor
  the v1.3.3 tag's `sources/`, `headers/` and `LICENSE`, checked against Homebrew's sha256, and scan it again as
  before (stdout only, no network, no processes); `make app` must still build it with `-Werror`. Check on the LG pair
  that 200 back-to-back reads at 100 % give no wrong value, and that a monitor answering exit 1 is left alone (T-171).
  Then drop every mention of the patch: `Vendor/m1ddc/README.md`, About's "m1ddc 1.3.1 (patched)"
  (`SettingsView.swift`), the README's License line, `SECURITY.md`, `REQUIREMENTS.md` (m1ddc lines), `reference/app.md`
  (m1ddc; "Homebrew's stock m1ddc can still print a bad `0`" holds only before 1.3.3). Ships with the next release.
  (owner, 22/11/2026)
- BL-041 [P2] [feature] A website's own icon, fetched by DeckOut. Today a key or knob-list item that opens a website
  shows only an icon chosen by hand (picture, text or library symbol). The app would fetch the site's icon when the
  address is set: the page's declared icons (prefer a large one such as `apple-touch-icon`), else `/favicon.ico`,
  saved as a PNG in `icons/` like any other icon, never re-fetched by the agent. Trade-offs: the app starts going
  online, which it doesn't today; it parses pages and decodes images from sites it doesn't control (size caps,
  timeouts, ImageIO only, nothing executed); many sites offer only 16–32 px, blurry on a 176 × 112 block; some offer
  none (fall back to a text tile). A favicon service (Google's, DuckDuckGo's), not the site itself, is ruled out:
  it would learn the person's list of sites. Deferred from the knob lists design, which picks icons by hand
  (`docs/design/knob_lists.md`). `IconRow.swift`, `IconFiles.swift` (owner, 26/11/2026)
- BL-042 [P1] [bug] Both decks, on different USB ports, go out of whack around the same time. The owner suspects the
  agent and / or the app: earlier failures hit one deck at a time. Seen 26/11/2026 (times from the kernel log):
  - The N3 (dock port) dropped all afternoon under the signed 2.1.0 agent: "hardware connection lost" at 14:05, 14:33,
    15:05, 16:01; "Retries exhausted" then "reset API call" at 17:06, 17:14, 17:21; more at 17:22, 17:24, 18:11,
    18:18, 18:41. Each time back at 480 Mbps.
  - The N4 (LG monitor port): transaction errors on its input endpoint 0x82 at 17:53:43–47, then macOS reset the N4
    and its built-in hub chip (05e3:0610). Both came back at 12 Mbps at 17:53:49, with the 2.1.0 agent alone running
    and no tests running. At 12 Mbps every press is a babble error and a reset (~220 between 18:06 and 18:16). It
    stayed there until the owner re-plugged both decks (18:40:50 / 18:41:00, 480 Mbps).
  - 18:15–18:21: the 2.1.0 agent and a DeckOut Dev agent ran at once, both drawing both decks (a test-session slip).
  Against the agent: the code that opens and talks to the decks (`DeckManager`, `DeckConnection`, `Packets`,
  `DeckModel`) is byte-identical in v2.0.0, v2.1.0 and `knob-lists`; that code ran ~17 h with no drops on 23–24/11.
  DeckOut can't pick the link speed. For it: the agent writes to both decks constantly (a keepalive every 5 s; new
  images whenever a live strip block changes), so a firmware hang from something it sends can't be ruled out from
  logs. Next: a control run with DeckOut stopped (Stop and Remove) and both decks plugged in for hours, then read the
  kernel log. Drops with DeckOut stopped clear it; none points at the agent: then the same run with DeckOut but no
  live strip blocks, then with no keepalive. Query (the kernel log keeps only ~14 h): `/usr/bin/log show --last 3h
  --predicate 'process == "kernel" AND (eventMessage CONTAINS "enumerated 0x" OR eventMessage CONTAINS
  "terminateDevice" OR eventMessage CONTAINS "Retries exhausted")' --style compact`; N4 = 0x6602, N3 = 0x5548.
  `DeckManager.swift`, `DeckConnection.swift`, `Daemon.swift` (`tick`, `redrawLive`) (owner, 26/11/2026)

