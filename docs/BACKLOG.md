# Backlog

Items discovered during builds, reviews, or revisits. Not blocking current work.
Promote to `TODO.md` when ready to tackle.

Use priority tags: `[P0]` `[P1]` `[P2]` and domain tags: `[security]` `[feature]` `[bug]` `[debt]`

Next free ID: BL-044

---

### Open

- BL-002 [P2] [feature] No handling for the Mac waking from system sleep. If a deck keeps power through sleep but resets
  without re-enumerating, its keys could show the deck's own logo until the next lock / unlock or replug. On
  `NSWorkspace.didWakeNotification`: re-run the start-up sequence, redraw, recheck the lock. Untested here — this Mac
  never system-sleeps. `Daemon.swift` (19/11/2026)
- BL-029 [P2] [feature] Live strip blocks a person can add (the weather, a build status, a price). Today the three
  live readings (internet, CPU and memory, volume) are written into the agent, so each new one needs code. Owner
  (20/11/2026): new kinds are not built into the app; they are scripts in a `blocks/` folder, which the agent runs on
  an interval and draws as short text. Idea, with the looks the owner approved on the N4 (text, `color=`, emoji,
  `icon=` symbols, a test card on failure) and the open scripting and scheduling questions:
  `docs/ideas/script_blocks.md`. Initial work: its first slice (a weather script, the agent's runner, a `script` block
  set by hand). After the phase 7 release, once the scripting and scheduling are worked out (owner, 21/11/2026).
  `StripBlockType`, `StripRenderer`, `Daemon.swift` (UAT, 20/11/2026)
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
- BL-043 [P2] [debt] Knob lists review minors (fresh opus review of `knob-lists`, deferred 26/11/2026): a list item
  running a non-executable script shows the problem but no Make Executable button; the "strip block N's own setting
  is set aside" line prints only at start-up, not on app or swipe reloads (no test); the load-time Accessibility
  warning and load summary cover only the live preset's knobs, so a `key:` item in another preset warns only when it
  goes live; T-207 doesn't exercise the agent's `start()` wiring, and no test checks that the agent's `next_preset`
  save keeps a list; a fresh install's second save makes a `.before-2.2` copy of a file 2.2 wrote (as `.before-app`
  does); the knob ↔ block mapping is written in four places; `KnobConfig.list` is a public var beside rotate / press
  that mean nothing for a list. (The fast-spin lag it raised was measured on the deck: redraw median 4 ms.)
  `Daemon.swift`, `Agent.swift`, `ConfigFile.swift`, `Config.swift` (owner, 26/11/2026)
