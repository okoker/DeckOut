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
- BL-043 [P2] [bug] A knob list item set to a script that isn't executable shows the problem but no Make Executable
  button, as a key or a strip block has: the list's problem note is built with no action (`ProblemNote(…, choice:
  .nothing)`), so the button's script check never matches. A person adding a new script to a list has to `chmod +x`
  it in Terminal. Pass the item with the problem instead. `KnobEditor.swift` (knob lists review, owner, 26/11/2026)
